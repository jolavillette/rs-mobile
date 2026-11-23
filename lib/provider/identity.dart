import 'package:flutter/cupertino.dart';
import 'package:retroshare/model/http_exception.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

class Identities with ChangeNotifier {
  List<Identity> _ownidentities = [];
  Identity? _selected;
  AuthToken? _authToken;
  String? _pgpPassword;
  set authToken(AuthToken? authToken) {
    _authToken = authToken;
  }
  set pgpPassword(String? pgpPassword) {
    _pgpPassword = pgpPassword;
  }

  AuthToken? get authToken => _authToken;

  List<Identity> get ownIdentity => _ownidentities;
  Identity? _currentIdentity;
  Identity? get currentIdentity => _currentIdentity;

  Future<void> fetchOwnidenities() async {
    if (_authToken == null) {
      return;
    }
    _ownidentities = await getOwnIdentities(_authToken!);
    if (_ownidentities.isNotEmpty) {
      _currentIdentity = _ownidentities[0];
      _selected = _ownidentities[0];
    }
    notifyListeners();
  }

  Identity? get selectedIdentity => _selected;

  void updateCurrentIdentity() {
    if (_selected != null) {
      _currentIdentity = _selected;
    }
    notifyListeners();
  }

  void updateSelectedIdentity(Identity id) {
    if (_selected == null) {
      _selected = id;
      notifyListeners();
    } else if (_selected!.mId != id.mId) {
      _selected = id;
      notifyListeners();
    }
  }

  Future<void> createNewIdenity(Identity id, RsGxsImage image) async {
    if (_authToken == null) {
      return;
    }
    final newIdentity = await RsIdentity.createIdentity(id, image, _authToken!, _pgpPassword);
    _ownidentities.add(newIdentity);
    _currentIdentity = newIdentity;
    _selected = _currentIdentity;
    notifyListeners();
  }

  /// Deletes [identity], one of ours but never the active one: the user
  /// switches to another identity first.
  Future<void> deleteIdentity(Identity identity) async {
    if (_authToken == null) {
      return;
    }
    if (_currentIdentity?.mId == identity.mId) {
      throw Exception('The active identity cannot be deleted');
    }

    try {
      final success = await RsIdentity.deleteIdentity(identity, _authToken!);
      if (!success) throw HttpException('BAD REQUEST');
      _ownidentities.removeWhere((element) => element.mId == identity.mId);
      if (_selected?.mId == identity.mId) {
        _selected = _currentIdentity;
      }
      notifyListeners();
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> updateIdentity(Identity id, RsGxsImage avatar) async {
    if (_authToken == null) {
      return;
    }

    final success = await RsIdentity.updateIdentity(id, avatar, _authToken!, _pgpPassword);
    if (!success) {
      throw 'Try Again';
    }
    
    // Refresh to get the latest details from the core (including PGP info if applicable)
    await fetchOwnidenities();
    
    // Fallback if the list didn't include the updated ID for some reason
    var found = false;
    for (var i = 0; i < _ownidentities.length; i++) {
      if (_ownidentities[i].mId == id.mId) {
        _ownidentities[i] = id;
        _currentIdentity = _ownidentities[i];
        found = true;
        break;
      }
    }
    
    if (!found) {
      _currentIdentity = id;
    }

    _selected = _currentIdentity;
    notifyListeners();
  }
}
