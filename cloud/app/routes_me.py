from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from .db import User, get_session
from .security import get_current_user

router = APIRouter(tags=["me"])


class UserOut(BaseModel):
    id: int
    email: str
    display_name: str


class UpdateMeBody(BaseModel):
    display_name: str = Field(min_length=1, max_length=120)


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)):
    return UserOut(id=user.id, email=user.email, display_name=user.display_name)


@router.patch("/me", response_model=UserOut)
def update_me(
    body: UpdateMeBody,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_session),
):
    user.display_name = body.display_name.strip()[:120]
    db.add(user)
    db.commit()
    db.refresh(user)
    return UserOut(id=user.id, email=user.email, display_name=user.display_name)
