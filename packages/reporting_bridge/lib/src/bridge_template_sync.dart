import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'bridge_cache_namespace.dart';
import 'bridge_http_fetch.dart';
import 'bridge_runtime_error.dart';
import 'bridge_template_cache.dart';
import 'bridge_template_query.dart';

const List<String> kPresenterBridgeApprovedHeaderNames = <String>[
  'Authorization',
  'X-Tenant-Id',
  'X-Branch-Id',
  'X-User-Context',
];

abstract final class BridgeTemplateSyncErrorCodes {
  static const String systemNotFound = 'SYSTEM_NOT_FOUND';
  static const String identityContextConflict = 'IDENTITY_CONTEXT_CONFLICT';
  static const String templateQueryFailed = 'TEMPLATE_QUERY_FAILED';
  static const String templateCatalogInvalid = 'TEMPLATE_CATALOG_INVALID';
  static const String offlineCacheUnavailable = 'OFFLINE_CACHE_UNAVAILABLE';
}

Map<String, String> filterPresenterBridgeHeaders(Map<String, String> raw) {
  final normalized = <String, String>{
    for (final entry in raw.entries)
      entry.key.toLowerCase(): entry.value.trim(),
  };
  final out = <String, String>{};
  for (final name in kPresenterBridgeApprovedHeaderNames) {
    final value = normalized[name.toLowerCase()];
    if (value != null && value.isNotEmpty) out[name] = value;
  }
  return out;
}

class PresenterTemplateSyncService {
  PresenterTemplateSyncService({
    HttpClient Function()? httpClientFactory,
    Duration timeout = const Duration(seconds: 8),
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _timeout = timeout,
       _legacyHttp = BridgeHttpFetch(
         httpClientFactory: httpClientFactory,
         timeout: timeout,
       );

  final HttpClient Function() _httpClientFactory;
  final Duration _timeout;
  final BridgeHttpFetch _legacyHttp;

  static const String _queryPath = 'presenter/templates/query';
  static const String _listPath = 'presenter/templates';
  static const String _detailPathPrefix = 'presenter/templates/';

  Future<TemplateSyncSummary> queryTemplatesToCache({
    required Uri apiBase,
    required Map<String, String> headers,
    required TemplateCacheService cache,
    required TemplateQueryRequest request,
  }) async {
    final filtered = filterPresenterBridgeHeaders(headers);
    _validateIdentityHeaders(filtered, request);
    final queryUri = resolveBridgeApiRoute(apiBase, _queryPath);

    Map<String, dynamic> payload;
    try {
      payload = await _postJsonObject(
        queryUri,
        headers: filtered,
        body: request.toJson(),
      );
    } on _TemplateTransportException catch (error) {
      final metadata = await cache.readCatalogMetadata();
      if (_metadataMatchesRequest(metadata, request)) {
        final cached = await cache.listTemplates();
        return TemplateSyncSummary(
          syncedCount: cached.length,
          listCount: cached.length,
          errors: const <String>[],
          fromCache: true,
          cacheReason: error.message,
          catalogRevision: metadata?.catalogRevision,
          systemCode: request.systemCode,
          systemId: metadata?.systemId,
          systemName: metadata?.systemName,
          systemDescription: metadata?.systemDescription,
          appliedFilter: metadata?.appliedFilter,
        );
      }
      throw BridgeRuntimeException(
        BridgeTemplateSyncErrorCodes.offlineCacheUnavailable,
        'No cached template catalog is available for the current scope: '
        '${error.message}',
      );
    }

    _throwIfBackendFailure(payload, queryUri);
    final parsed = _parseQueryResponse(payload, request);
    await _replaceQueryCacheAtomically(
      cache: cache,
      downloaded: parsed.templates,
      metadata: TemplateCatalogMetadata(
        catalogRevision: parsed.catalogRevision,
        systemCode: request.systemCode,
        systemName: parsed.systemName,
        systemDescription: parsed.systemDescription,
        filterFingerprint: request.filterFingerprint,
        extraFingerprint: request.extraFingerprint,
        systemId: parsed.systemId,
        appliedFilter: parsed.appliedFilter,
      ),
    );

    return TemplateSyncSummary(
      syncedCount: parsed.templates.length,
      listCount: parsed.templates.length,
      errors: const <String>[],
      catalogRevision: parsed.catalogRevision,
      systemCode: request.systemCode,
      systemId: parsed.systemId,
      systemName: parsed.systemName,
      systemDescription: parsed.systemDescription,
      appliedFilter: parsed.appliedFilter,
    );
  }

  @Deprecated('Use queryTemplatesToCache with systemCode.')
  Future<TemplateSyncSummary> syncTemplatesToCache({
    required Uri apiBase,
    required Map<String, String> headers,
    required TemplateCacheService cache,
    int? systemId,
  }) async {
    if (systemId != null && systemId <= 0) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Template synchronization requires a positive systemId.',
      );
    }

    final filtered = filterPresenterBridgeHeaders(headers);
    final baseListUri = resolveBridgeApiRoute(apiBase, _listPath);
    final listUri = systemId == null
        ? baseListUri
        : baseListUri.replace(
            queryParameters: <String, String>{'systemId': '$systemId'},
          );
    final listPayload = await _legacyHttp.getJsonObject(
      listUri,
      headers: filtered,
      notValidJsonMessage: 'Response from $listUri is not valid JSON.',
    );
    if (listPayload['success'] != true) {
      throw BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Presenter template list response not successful: $listUri',
      );
    }

    final data = unwrapBridgeEnvelopeData(listPayload);
    final rawItems = data['items'];
    if (rawItems is! List) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Presenter template list missing data.items array.',
      );
    }

    if (systemId != null && rawItems.isEmpty) {
      return TemplateSyncSummary(
        syncedCount: 0,
        listCount: 0,
        errors: <String>[
          'No published templates are available for system $systemId; '
              'the existing cache was preserved.',
        ],
      );
    }

    final downloaded = <CachedTemplate>[];
    final ids = <String>{};
    final errors = <String>[];

    for (var index = 0; index < rawItems.length; index++) {
      final raw = rawItems[index];
      if (raw is! Map) {
        errors.add('Template list item $index is not an object');
        continue;
      }

      final id = raw['id']?.toString().trim();
      if (id == null || id.isEmpty) {
        errors.add('Template list item $index is missing id');
        continue;
      }
      if (!ids.add(id)) {
        errors.add('Template $id appears more than once in the list');
        continue;
      }

      if (systemId != null) {
        final listedSystemId = int.tryParse(raw['systemId']?.toString() ?? '');
        if (listedSystemId != systemId) {
          errors.add(
            'Template $id belongs to system ${raw['systemId']}; '
            'expected $systemId',
          );
          continue;
        }
      }

      final detailUri = resolveBridgeApiRoute(
        apiBase,
        '$_detailPathPrefix${Uri.encodeComponent(id)}/latest',
      );
      try {
        final detailPayload = await _legacyHttp.getJsonObject(
          detailUri,
          headers: filtered,
          notValidJsonMessage: 'Response from $detailUri is not valid JSON.',
        );
        if (detailPayload['success'] != true) {
          errors.add('Template $id: response not successful');
          continue;
        }

        final template = CachedTemplate.fromMap(
          unwrapBridgeEnvelopeData(detailPayload),
        );
        if (template.id != id) {
          errors.add('Template $id: detail response id is ${template.id}');
          continue;
        }
        if (systemId != null && template.systemId != systemId) {
          errors.add(
            'Template $id: detail systemId is ${template.systemId}; '
            'expected $systemId',
          );
          continue;
        }
        downloaded.add(template);
      } catch (error) {
        errors.add('Template $id: $error');
      }
    }

    if (errors.isNotEmpty) {
      return TemplateSyncSummary(
        syncedCount: 0,
        listCount: rawItems.length,
        errors: List<String>.unmodifiable(errors),
      );
    }

    await _replaceLegacyCacheAtomically(
      cache: cache,
      systemId: systemId,
      downloaded: downloaded,
    );

    return TemplateSyncSummary(
      syncedCount: downloaded.length,
      listCount: rawItems.length,
      errors: const <String>[],
    );
  }

  bool _metadataMatchesRequest(
    TemplateCatalogMetadata? metadata,
    TemplateQueryRequest request,
  ) {
    return metadata != null &&
        metadata.systemCode == request.systemCode &&
        metadata.filterFingerprint == request.filterFingerprint &&
        metadata.extraFingerprint == request.extraFingerprint;
  }

  Future<Map<String, dynamic>> _postJsonObject(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, dynamic> body,
  }) async {
    final client = _httpClientFactory();
    client.connectionTimeout = _timeout;
    try {
      final request = await client.postUrl(uri).timeout(_timeout);
      headers.forEach(request.headers.set);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      request.write(jsonEncode(body));
      final response = await request.close().timeout(_timeout);
      final bytes = <int>[];
      await for (final chunk in response.timeout(_timeout)) {
        bytes.addAll(chunk);
      }

      Map<String, dynamic>? payload;
      if (bytes.isNotEmpty) {
        try {
          final decoded = jsonDecode(utf8.decode(bytes));
          if (decoded is Map<String, dynamic>) {
            payload = decoded;
          } else if (decoded is Map) {
            payload = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {
          payload = null;
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (payload != null) {
          _throwBackendError(payload, uri, response.statusCode);
        }
        final code = response.statusCode == HttpStatus.notFound
            ? BridgeTemplateSyncErrorCodes.systemNotFound
            : BridgeTemplateSyncErrorCodes.templateQueryFailed;
        throw BridgeRuntimeException(
          code,
          'HTTP ${response.statusCode} while querying $uri.',
        );
      }
      if (payload == null) {
        throw BridgeRuntimeException(
          BridgeTemplateSyncErrorCodes.templateCatalogInvalid,
          'Response from $uri is not a JSON object.',
        );
      }
      return payload;
    } on TimeoutException {
      throw _TemplateTransportException('Request timed out: $uri');
    } on SocketException catch (error) {
      throw _TemplateTransportException('Request failed ($uri): $error');
    } on HttpException catch (error) {
      throw _TemplateTransportException('Request failed ($uri): $error');
    } on _TemplateTransportException {
      rethrow;
    } on BridgeRuntimeException {
      rethrow;
    } catch (error) {
      throw _TemplateTransportException('Request failed ($uri): $error');
    } finally {
      client.close(force: true);
    }
  }

  void _validateIdentityHeaders(
    Map<String, String> headers,
    TemplateQueryRequest request,
  ) {
    final headerBranch = bridgeHeaderValue(headers, 'X-Branch-Id');
    final bodyBranch = request.identity.branchId;
    if (headerBranch != null &&
        bodyBranch != null &&
        headerBranch != bodyBranch) {
      throw const BridgeRuntimeException(
        BridgeTemplateSyncErrorCodes.identityContextConflict,
        'Bridge identity branchId conflicts with X-Branch-Id.',
      );
    }

    final headerUser = bridgeHeaderValue(headers, 'X-User-Context');
    final bodyUser = request.identity.userId;
    if (headerUser != null && bodyUser != null && headerUser != bodyUser) {
      throw const BridgeRuntimeException(
        BridgeTemplateSyncErrorCodes.identityContextConflict,
        'Bridge identity userId conflicts with X-User-Context.',
      );
    }
  }

  void _throwIfBackendFailure(Map<String, dynamic> payload, Uri uri) {
    if (payload['success'] == true) return;
    _throwBackendError(payload, uri, null);
  }

  Never _throwBackendError(
    Map<String, dynamic> payload,
    Uri uri,
    int? statusCode,
  ) {
    final error = payload['error'];
    String? code;
    String? message;
    if (error is Map) {
      code = _nonEmptyString(error['code'] ?? error['error']);
      message = _nonEmptyString(
        error['message'] ?? error['detail'] ?? error['description'],
      );
    } else if (error != null) {
      code = _nonEmptyString(error);
    }
    code ??= _nonEmptyString(payload['code']);
    message ??= _nonEmptyString(
      payload['message'] ?? payload['detail'] ?? payload['error_description'],
    );

    final effectiveCode =
        code ??
        (statusCode == HttpStatus.notFound
            ? BridgeTemplateSyncErrorCodes.systemNotFound
            : BridgeTemplateSyncErrorCodes.templateQueryFailed);
    final statusSuffix = statusCode == null ? '' : ' (HTTP $statusCode)';
    final effectiveMessage =
        message ?? 'Presenter template query failed$statusSuffix: $uri';
    throw BridgeRuntimeException(effectiveCode, effectiveMessage);
  }

  _ParsedTemplateCatalog _parseQueryResponse(
    Map<String, dynamic> payload,
    TemplateQueryRequest request,
  ) {
    final data = unwrapBridgeEnvelopeData(payload);
    final revision = _nonEmptyString(data['catalogRevision']);
    final system = data['system'];
    final appliedFilter = data['appliedFilter'];
    final rawItems = data['items'];
    final rawCount = int.tryParse(data['count']?.toString() ?? '');
    if (revision == null ||
        system is! Map ||
        appliedFilter is! Map ||
        rawItems is! List ||
        rawCount == null ||
        rawCount < 0) {
      throw const BridgeRuntimeException(
        BridgeTemplateSyncErrorCodes.templateCatalogInvalid,
        'Template query response requires catalogRevision, system, '
        'appliedFilter, count, and items.',
      );
    }
    if (rawCount != rawItems.length) {
      throw BridgeRuntimeException(
        BridgeTemplateSyncErrorCodes.templateCatalogInvalid,
        'Template query count $rawCount does not match '
        '${rawItems.length} items.',
      );
    }

    final responseSystemCode = _nonEmptyString(
      system['code'],
    )?.trim().toLowerCase();
    final responseSystemId = int.tryParse(system['id']?.toString() ?? '');
    final responseSystemName = _nonEmptyString(system['name']);
    final responseSystemDescription = _nonEmptyString(system['description']);
    if (responseSystemCode != request.systemCode ||
        responseSystemName == null ||
        responseSystemId == null ||
        responseSystemId <= 0) {
      throw BridgeRuntimeException(
        BridgeTemplateSyncErrorCodes.templateCatalogInvalid,
        'Template query response system does not match '
        '${request.systemCode}.',
      );
    }

    final templates = <CachedTemplate>[];
    final ids = <String>{};
    for (var index = 0; index < rawItems.length; index++) {
      final raw = rawItems[index];
      if (raw is! Map) {
        throw BridgeRuntimeException(
          BridgeTemplateSyncErrorCodes.templateCatalogInvalid,
          'Template query item $index is not an object.',
        );
      }
      late final CachedTemplate template;
      try {
        template = CachedTemplate.fromMap(raw);
      } on BridgeRuntimeException catch (error) {
        throw BridgeRuntimeException(
          BridgeTemplateSyncErrorCodes.templateCatalogInvalid,
          'Template query item $index is invalid: ${error.message}',
        );
      }
      if (!ids.add(template.id)) {
        throw BridgeRuntimeException(
          BridgeTemplateSyncErrorCodes.templateCatalogInvalid,
          'Template query contains duplicate id ${template.id}.',
        );
      }
      if (template.systemId != responseSystemId) {
        throw BridgeRuntimeException(
          BridgeTemplateSyncErrorCodes.templateCatalogInvalid,
          'Template ${template.id} belongs to system '
          '${template.systemId}; expected $responseSystemId.',
        );
      }
      templates.add(template);
    }

    return _ParsedTemplateCatalog(
      catalogRevision: revision,
      systemId: responseSystemId,
      systemName: responseSystemName,
      systemDescription: responseSystemDescription,
      appliedFilter: Map<String, dynamic>.unmodifiable(
        Map<String, dynamic>.from(appliedFilter),
      ),
      templates: List<CachedTemplate>.unmodifiable(templates),
    );
  }

  Future<void> _replaceQueryCacheAtomically({
    required TemplateCacheService cache,
    required List<CachedTemplate> downloaded,
    required TemplateCatalogMetadata metadata,
  }) async {
    final storedSelection = await cache.readSelectedTemplate();
    final root = cache.cacheRoot;
    await root.parent.create(recursive: true);
    final token = DateTime.now().microsecondsSinceEpoch;
    final staging = Directory('${root.path}.stage-$token');
    final backup = Directory('${root.path}.backup-$token');
    if (await staging.exists()) await staging.delete(recursive: true);
    if (await backup.exists()) await backup.delete(recursive: true);
    await staging.create(recursive: true);

    final stagedCache = TemplateCacheService(cacheRoot: staging);
    for (final template in downloaded) {
      await stagedCache.putTemplate(template);
    }
    await stagedCache.writeCatalogMetadata(metadata);
    if (storedSelection != null && metadata.systemCode != null) {
      await stagedCache.writeSelectedTemplate(storedSelection);
      await stagedCache.migrateSelectedTemplate(
        catalog: downloaded,
        systemCode: metadata.systemCode!,
      );
    }

    var originalMoved = false;
    var stagedInstalled = false;
    try {
      if (await root.exists()) {
        await root.rename(backup.path);
        originalMoved = true;
      }
      await staging.rename(root.path);
      stagedInstalled = true;
      if (originalMoved && await backup.exists()) {
        await backup.delete(recursive: true);
      }
    } catch (_) {
      if (stagedInstalled && await root.exists()) {
        await root.delete(recursive: true);
      }
      if (originalMoved && await backup.exists()) {
        await backup.rename(root.path);
      }
      rethrow;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
      if (await backup.exists() && await root.exists()) {
        await backup.delete(recursive: true);
      }
    }
  }

  Future<void> _replaceLegacyCacheAtomically({
    required TemplateCacheService cache,
    required int? systemId,
    required List<CachedTemplate> downloaded,
  }) async {
    final previous = await cache.listTemplates();
    final retained = systemId == null
        ? const <CachedTemplate>[]
        : previous
              .where((template) => template.systemId != systemId)
              .toList(growable: false);
    final incomingIds = downloaded.map((template) => template.id).toSet();
    for (final template in retained) {
      if (incomingIds.contains(template.id)) {
        throw BridgeRuntimeException(
          BridgeRuntimeErrorCodes.templateDocumentInvalid,
          'Template ${template.id} is already cached for system '
          '${template.systemId}.',
        );
      }
    }

    final root = cache.cacheRoot;
    await root.parent.create(recursive: true);
    final token = DateTime.now().microsecondsSinceEpoch;
    final staging = Directory('${root.path}.stage-$token');
    final backup = Directory('${root.path}.backup-$token');
    if (await staging.exists()) await staging.delete(recursive: true);
    if (await backup.exists()) await backup.delete(recursive: true);
    await staging.create(recursive: true);

    final stagedCache = TemplateCacheService(cacheRoot: staging);
    for (final template in <CachedTemplate>[...retained, ...downloaded]) {
      await stagedCache.putTemplate(template);
    }
    await stagedCache.writeCatalogMetadata(
      TemplateCatalogMetadata(
        catalogRevision: 'legacy-get',
        systemCode: null,
        filterFingerprint: null,
        extraFingerprint: null,
      ),
    );

    var originalMoved = false;
    var stagedInstalled = false;
    try {
      if (await root.exists()) {
        await root.rename(backup.path);
        originalMoved = true;
      }
      await staging.rename(root.path);
      stagedInstalled = true;
      if (originalMoved && await backup.exists()) {
        await backup.delete(recursive: true);
      }
    } catch (_) {
      if (stagedInstalled && await root.exists()) {
        await root.delete(recursive: true);
      }
      if (originalMoved && await backup.exists()) {
        await backup.rename(root.path);
      }
      rethrow;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
      if (await backup.exists() && await root.exists()) {
        await backup.delete(recursive: true);
      }
    }
  }
}

class TemplateSyncSummary {
  const TemplateSyncSummary({
    required this.syncedCount,
    required this.listCount,
    required this.errors,
    this.fromCache = false,
    this.cacheReason,
    this.catalogRevision,
    this.systemCode,
    this.systemId,
    this.systemName,
    this.systemDescription,
    this.appliedFilter,
  });

  final int syncedCount;
  final int listCount;
  final List<String> errors;
  final bool fromCache;
  final String? cacheReason;
  final String? catalogRevision;
  final String? systemCode;
  final int? systemId;
  final String? systemName;
  final String? systemDescription;
  final Map<String, dynamic>? appliedFilter;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'syncedCount': syncedCount,
    'listCount': listCount,
    'errors': errors,
    'fromCache': fromCache,
    if (cacheReason != null) 'cacheReason': cacheReason,
    if (catalogRevision != null) 'catalogRevision': catalogRevision,
    if (systemCode != null) 'systemCode': systemCode,
    if (systemId != null) 'systemId': systemId,
    if (systemName != null) 'systemName': systemName,
    if (systemDescription != null) 'systemDescription': systemDescription,
    if (appliedFilter != null) 'appliedFilter': appliedFilter,
  };
}

final class _ParsedTemplateCatalog {
  const _ParsedTemplateCatalog({
    required this.catalogRevision,
    required this.systemId,
    required this.systemName,
    required this.systemDescription,
    required this.appliedFilter,
    required this.templates,
  });

  final String catalogRevision;
  final int systemId;
  final String systemName;
  final String? systemDescription;
  final Map<String, dynamic> appliedFilter;
  final List<CachedTemplate> templates;
}

final class _TemplateTransportException implements Exception {
  const _TemplateTransportException(this.message);

  final String message;
}

String? _nonEmptyString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
