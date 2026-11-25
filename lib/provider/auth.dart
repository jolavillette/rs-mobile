import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:retroshare/apiUtils/mobile_services.dart';
import 'package:retroshare/apiUtils/retroshare_service.dart' as mobile_service;
import 'package:retroshare_api_wrapper/retroshare.dart';
import 'package:shared_preferences/shared_preferences.dart';

String deriveApiToken(String locationId, String password) {
  final bytes = utf8.encode('$locationId:$password');
  return sha256.convert(bytes).toString();
}

class AccountCredentials with ChangeNotifier {
  List<Account> _accountsList = [];
  Account? _lastAccountUsed;
  Account? _loggedinAccount;
  AuthToken? _authToken;
  String? _pgpPassword;
  Account? get lastAccountUsed => _lastAccountUsed;
  List<Account> get accountList => _accountsList;
  Account? get loggedinAccount => _loggedinAccount;
  AuthToken? get getAuthToken => _authToken;
  String? get getPgpPassword => _pgpPassword;

  set logginAccount(Account acc) {
    _loggedinAccount = acc;
    _rememberAccount(acc);
  }

  static const _lastLocationKey = 'last_location_id';

  /// The node last logged in is the one the sign-in screen offers first, as
  /// on the desktop. Kept on the device: before a login the core cannot say
  /// which one it was.
  void _rememberAccount(Account acc) {
    _lastAccountUsed = acc;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_lastLocationKey, acc.locationId))
        .catchError((Object e) {
      debugPrint('Cannot remember the last node: $e');
      return false;
    });
  }

  Future<Account?> _rememberedAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_lastLocationKey);
      for (final account in _accountsList) {
        if (account.locationId == id) return account;
      }
    } catch (e) {
      debugPrint('Cannot read the last node: $e');
    }
    return null;
  }

  AuthToken? get authtoken => _authToken;

  Future<void> fetchAuthAccountList() async {
    try {
      final resp = await RsLoginHelper.getLocations();
      final accountsList = <Account>[];
      resp.forEach((location) {
        if (location != null) {
          accountsList.add(
            Account(
              locationId: location['mLocationId'],
              pgpId: location['mPgpId'],
              locationName: location['mLocationName'],
              pgpName: location['mPgpName'],
            ),
          );
        }
      });
      _accountsList = [];
      _accountsList = accountsList;
      _lastAccountUsed = await setLastAccountUsed();
      notifyListeners();
    } catch (e) {
      throw HttpException(e.toString());
    }
  }

  Account? get getlastAccountUsed => _lastAccountUsed;

  Future<Account?> setLastAccountUsed() async {
    final remembered = await _rememberedAccount();
    if (_authToken == null) {
      return remembered;
    }
    final currAccount = await RsAccounts.getCurrentAccountId(_authToken!);
    for (final account in _accountsList) {
      if (account.locationId == currAccount) return account;
    }
    if (remembered != null) return remembered;
    // Return the first account if available, otherwise throw
    if (_accountsList.isNotEmpty) {
      return _accountsList.first;
    }
    throw Exception('No account found for setLastAccountUsed');
  }

  Future<bool> getinitializeAuth(Account account, String password) async {
    final token =
        AuthToken(account.pgpName, deriveApiToken(account.pgpName, password));
    _authToken = token;

    // The core may already have the location unlocked without retaining the
    // API user requested by this Flutter process. This happens most often
    // after the Android activity is recreated while the backend service keeps
    // running. Repair the token through the location's built-in credentials.
    for (var retry = 0; retry < 3; retry++) {
      if (retry > 0) {
        await Future.delayed(const Duration(seconds: 1));
      }

      if (await RsJsonApi.isAuthTokenValid(token)) {
        await turnOffOptionalServices(token, account.locationId);
        return true;
      }

      try {
        await RsJsonApi.checkExistingAuthTokens(
          account.locationId,
          password,
          token,
        );
        if (await RsJsonApi.isAuthTokenValid(token)) {
          await turnOffOptionalServices(token, account.locationId);
          return true;
        }
      } catch (error) {
        debugPrint('Unable to restore the RetroShare API token: $error');
      }
    }

    return false;
  }

  Future<bool> checkIsValidAuthToken() async {
    return _authToken == null ? false : RsJsonApi.isAuthTokenValid(_authToken!);
  }

  Future<void> login(Account currentAccount, String password) async {
    await _restartBackendIfLoggedIn();
    final int resp = await RsLoginHelper.requestLogIn(
      currentAccount,
      password,
      currentAccount.pgpName,
      deriveApiToken(currentAccount.pgpName, password),
    );
    logginAccount = currentAccount;
    // Login success 0, already logged in 1
    if (resp == 0 || resp == 1) {
      _pgpPassword = password;
      final isAuthTokenValid =
          await getinitializeAuth(currentAccount, password);
      if (!isAuthTokenValid) {
        throw const HttpException('AUTHTOKEN FAILED');
      }
      notifyListeners();
    } else if (resp == 2) {
      throw const HttpException('WRONG PASSWORD');
    } else {
      throw HttpException('LOGIN FAILED (code $resp)');
    }
  }

  Future<void> signup(
    String username,
    String password,
    String nodename,
  ) async {
    await _restartBackendIfLoggedIn();

    final resp = await rsApiCall(
      '/rsLoginHelper/createLocationV2',
      params: {
        'locationId': '',
        'pgpId': '',
        'locationName': nodename,
        'pgpName': username,
        'password': password,
        'apiUser': username,
        'apiPass': deriveApiToken(username, password),
      },
    );
    print('DEBUG signup response: $resp');
    final account = (
      resp['retval']['errorNumber'] == 0,
      Account(
        locationId: resp['locationId'],
        pgpId: resp['pgpId'],
        locationName: nodename,
        pgpName: username,
      ),
    );
    if (account.$1) {
      _pgpPassword = password;
      _accountsList.add(account.$2);
      logginAccount = account.$2;
      final isAuthTokenValid = await getinitializeAuth(account.$2, password);
      if (!isAuthTokenValid) throw const HttpException('AUTHTOKEN FAILED');

      notifyListeners();
    } else {
      print('DEBUG signup failed. retval: ${resp['retval']}');
      throw const HttpException('DATA INSUFFICIENT');
    }
  }

  Future<bool> _restartBackendIfLoggedIn() async {
    if (!await RsLoginHelper.checkLoggedIn()) return false;

    await mobile_service.RsServiceControl.stopRetroshare();
    if (!await mobile_service.RsServiceControl.startRetroshare()) {
      throw const HttpException('RetroShare service failed to restart');
    }
    _authToken = null;
    _loggedinAccount = null;
    _pgpPassword = null;
    return true;
  }

  Future<void> importAccount(String base64Cert, String password) async {
    try {
      await _restartBackendIfLoggedIn();
      final resp = await RsLoginHelper.importLocation(base64Cert, password);
      if (resp['retval'] == true ||
          (resp['retval'] is Map && resp['retval']['errorNumber'] == 0)) {
        await fetchAuthAccountList();
        notifyListeners();
      } else {
        throw HttpException(resp['retval']?['errorMessage'] ?? 'Import failed');
      }
    } catch (e) {
      throw HttpException(e.toString());
    }
  }

  Future<void> importIdentityAndCreateLocation(
    String pgpKeyContent,
    String password, {
    required String nodeName,
  }) async {
    try {
      await _restartBackendIfLoggedIn();
      final importResp = await rsApiCall(
        '/rsAccounts/importIdentityFromString',
        params: {'data': pgpKeyContent},
      );
      if (!_isSuccessfulResult(importResp['retval'])) {
        throw HttpException(
          _apiErrorMessage(importResp, 'The PGP profile could not be imported'),
        );
      }

      final pgpId = (importResp['pgpId'] ?? importResp['gpgId'])?.toString();
      if (pgpId == null || pgpId.isEmpty) {
        throw const HttpException(
          'The imported profile did not return a PGP ID',
        );
      }

      final locationName = nodeName.trim();
      final apiUser = 'mobile-$pgpId';
      final apiPass = deriveApiToken(apiUser, password);
      final createResp = await rsApiCall(
        '/rsLoginHelper/createLocationV2',
        params: {
          'pgpId': pgpId,
          'locationName': locationName,
          // The core ignores pgpName when an existing pgpId is supplied.
          'pgpName': '',
          'password': password,
          'apiUser': apiUser,
          'apiPass': apiPass,
        },
      );
      if (!_isSuccessfulResult(createResp['retval'])) {
        throw HttpException(
          _apiErrorMessage(
            createResp,
            'Could not create a location from this profile',
          ),
        );
      }

      _pgpPassword = password;
      _authToken = AuthToken(apiUser, apiPass);
      final locationId = createResp['locationId']?.toString();
      if (locationId != null) {
        await turnOffOptionalServices(_authToken!, locationId);
      }
      await fetchAuthAccountList();

      Account? importedAccount;
      for (final account in _accountsList) {
        if ((locationId != null && account.locationId == locationId) ||
            account.pgpId == pgpId) {
          importedAccount = account;
          if (locationId != null && account.locationId == locationId) break;
        }
      }
      if (importedAccount == null) {
        throw const HttpException(
          'The new location was created but could not be found in the account list',
        );
      }
      _loggedinAccount = importedAccount;
      _rememberAccount(importedAccount);
      notifyListeners();
    } catch (e) {
      if (e is HttpException) rethrow;
      throw HttpException(e.toString());
    }
  }

  bool _isSuccessfulResult(dynamic result) {
    if (result is bool) return result;
    if (result is num) return result == 1 || result == 0;
    if (result is Map) return result['errorNumber'] == 0;
    return false;
  }

  String _apiErrorMessage(Map response, String fallback) {
    final retval = response['retval'];
    final message = response['errorMsg'] ??
        response['errorMessage'] ??
        (retval is Map ? retval['errorMessage'] : null);
    final text = message?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }
}
