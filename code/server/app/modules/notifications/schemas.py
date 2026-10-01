from pydantic import BaseModel


class NotificationUpdate(BaseModel):
    dismiss: bool = False
