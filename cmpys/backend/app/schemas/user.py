from datetime import date

from pydantic import BaseModel, EmailStr


class UserResponse(BaseModel):
    id: str
    email: EmailStr

    model_config = {"from_attributes": True}


class UserProfileResponse(BaseModel):
    id: str
    fullName: str | None = None
    birthDate: date | None = None
    focusAreas: list[str] | None = None
    timezone: str | None = None

    model_config = {"from_attributes": True}


class MeResponse(BaseModel):
    id: str
    email: EmailStr
    profile: UserProfileResponse | None = None

    model_config = {"from_attributes": True}


class UpdateProfileRequest(BaseModel):
    fullName: str | None = None
    birthDate: date | None = None
    focusAreas: list[str] | None = None
    timezone: str | None = None
