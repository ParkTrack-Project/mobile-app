import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';

@freezed
class User with _$User {
  const factory User({
    required int userId,
    required String email,
    String? fullName,
    required List<String> roles,
  }) = _User;
}
