from pydantic import AliasChoices, BaseModel, EmailStr, Field, field_validator


class PasswordRequest(BaseModel):
    password: str = Field(min_length=1, max_length=72)

    @field_validator("password")
    @classmethod
    def validate_password_bytes(cls, value: str) -> str:
        if len(value.encode("utf-8")) > 72:
            raise ValueError("Password must be no more than 72 UTF-8 bytes")
        return value


class RegisterRequest(PasswordRequest):
    full_name: str | None = Field(default=None, max_length=255, validation_alias=AliasChoices("full_name", "fullName"))
    email: EmailStr
    password: str = Field(min_length=8, max_length=72)


class LoginRequest(PasswordRequest):
    email: EmailStr


class TokenResponse(BaseModel):
    accessToken: str
    refreshToken: str


class RefreshTokenRequest(BaseModel):
    refreshToken: str
