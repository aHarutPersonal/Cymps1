from sqlalchemy import select, func
from sqlalchemy.orm import selectinload, declarative_base
from sqlalchemy import Column, Integer, String

Base = declarative_base()

class Note(Base):
    __tablename__ = 'notes'
    id = Column(Integer, primary_key=True)
    title = Column(String)

stmt = select(Note).where(Note.id == 1)
print("Original:")
print(stmt)

count_stmt = stmt.with_only_columns(func.count(Note.id)).order_by(None)
print("Count:")
print(count_stmt)
