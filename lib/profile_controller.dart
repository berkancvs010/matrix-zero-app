part of 'main.dart';

class ProfileController {
  ProfileController({required this.nickname});

  final String nickname;

  static const String photoKey = 'zerolog.profile.photo';
  static const String photoDataKey = 'zerolog.profile.photo_data';
  static const String aboutKey = 'zerolog.profile.about';

  String? photoPath;
  String photoData = '';
  String about = '';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    photoPath = prefs.getString(photoKey);
    photoData = prefs.getString(photoDataKey) ?? '';

    about = prefs.getString(aboutKey) ?? '';
  }

  Future<void> applyRemote(Map<String, dynamic> profile) async {
    final type = (profile['type'] ?? 'avatar').toString();

    final remoteAbout = (profile['about'] ?? '').toString();
    final remotePhoto = (profile['photoData'] ?? '').toString();
    final prefs = await SharedPreferences.getInstance();

    if (type == 'photo' && remotePhoto.isNotEmpty) {
      await prefs.setString(photoDataKey, remotePhoto);
      await prefs.remove(photoKey);
      photoPath = null;
      photoData = remotePhoto;
    } else if (type != 'photo') {
      await prefs.remove(photoKey);
      await prefs.remove(photoDataKey);
      photoPath = null;
      photoData = '';
    }

    if (profile.containsKey('about')) {
      await prefs.setString(aboutKey, remoteAbout);
      about = remoteAbout;
    }
  }

  Future<void> setPhotoData(String data) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(photoDataKey, data);
    await prefs.remove(photoKey);

    photoPath = null;
    photoData = data;
  }

  Future<void> clearPhoto() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(photoKey);
    await prefs.remove(photoDataKey);

    photoPath = null;
    photoData = '';
  }


  Future<void> setAbout(String value) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(aboutKey, value);
    about = value;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(photoKey);
    await prefs.remove(photoDataKey);
    await prefs.remove(aboutKey);

    photoPath = null;
    photoData = '';
    about = '';
  }
}
