import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_models.freezed.dart';
part 'auth_models.g.dart';

@freezed
class AuthResponseDto with _$AuthResponseDto {
  const factory AuthResponseDto({
    required String accessToken,
    required int expiresIn,
    required UserDto user,
  }) = _AuthResponseDto;

  factory AuthResponseDto.fromJson(Map<String, dynamic> json) =>
      _$AuthResponseDtoFromJson(json);
}

@freezed
class UserDto with _$UserDto {
  const factory UserDto({
    required int userId,
    required String email,
    String? fullName,
    required List<String> globalRoles,
  }) = _UserDto;

  factory UserDto.fromJson(Map<String, dynamic> json) =>
      _$UserDtoFromJson(json);
}

@freezed
class LoginRequestDto with _$LoginRequestDto {
  const factory LoginRequestDto({
    required String login,
    required String password,
  }) = _LoginRequestDto;

  factory LoginRequestDto.fromJson(Map<String, dynamic> json) =>
      _$LoginRequestDtoFromJson(json);
}

@freezed
class RegisterRequestDto with _$RegisterRequestDto {
  const factory RegisterRequestDto({
    required String email,
    required String password,
    String? fullName,
  }) = _RegisterRequestDto;

  factory RegisterRequestDto.fromJson(Map<String, dynamic> json) =>
      _$RegisterRequestDtoFromJson(json);
}
