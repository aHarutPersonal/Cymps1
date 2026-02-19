"""
Seed script to populate the database with sample idols and tags.

Run with: python -m app.scripts.seed_idols
"""
import asyncio
from datetime import date

from sqlalchemy import select

from app.core.db import async_session_maker
from app.models.idol import Idol
from app.models.idol_alias import IdolAlias
from app.models.idol_tag import IdolTag
from app.models.idol_tag_link import IdolTagLink


TAGS_DATA = [
    # Domain tags
    {"name": "business", "type": "domain"},
    {"name": "investing", "type": "domain"},
    {"name": "technology", "type": "domain"},
    {"name": "sports", "type": "domain"},
    {"name": "science", "type": "domain"},
    {"name": "entertainment", "type": "domain"},
    # Focus tags
    {"name": "entrepreneurship", "type": "focus"},
    {"name": "leadership", "type": "focus"},
    {"name": "innovation", "type": "focus"},
    {"name": "philanthropy", "type": "focus"},
    {"name": "ai", "type": "focus"},
    {"name": "space", "type": "focus"},
    {"name": "finance", "type": "focus"},
    {"name": "basketball", "type": "focus"},
    {"name": "acting", "type": "focus"},
]

IDOLS_DATA = [
    {
        "name": "Elon Musk",
        "birth_date": date(1971, 6, 28),
        "domain": "technology",
        "aliases": ["Elon Reeve Musk"],
        "tags": ["technology", "business", "entrepreneurship", "innovation", "ai", "space"],
    },
    {
        "name": "Warren Buffett",
        "birth_date": date(1930, 8, 30),
        "domain": "investing",
        "aliases": ["Oracle of Omaha"],
        "tags": ["investing", "business", "finance", "philanthropy"],
    },
    {
        "name": "Steve Jobs",
        "birth_date": date(1955, 2, 24),
        "domain": "technology",
        "aliases": ["Steven Paul Jobs"],
        "tags": ["technology", "business", "entrepreneurship", "innovation", "leadership"],
    },
    {
        "name": "Jeff Bezos",
        "birth_date": date(1964, 1, 12),
        "domain": "business",
        "aliases": ["Jeffrey Preston Bezos"],
        "tags": ["business", "technology", "entrepreneurship", "innovation", "space"],
    },
    {
        "name": "Bill Gates",
        "birth_date": date(1955, 10, 28),
        "domain": "technology",
        "aliases": ["William Henry Gates III"],
        "tags": ["technology", "business", "philanthropy", "entrepreneurship"],
    },
    {
        "name": "LeBron James",
        "birth_date": date(1984, 12, 30),
        "domain": "sports",
        "aliases": ["King James", "LBJ"],
        "tags": ["sports", "basketball", "business", "philanthropy"],
    },
    {
        "name": "Oprah Winfrey",
        "birth_date": date(1954, 1, 29),
        "domain": "entertainment",
        "aliases": ["Oprah Gail Winfrey"],
        "tags": ["entertainment", "business", "philanthropy", "leadership"],
    },
    {
        "name": "Albert Einstein",
        "birth_date": date(1879, 3, 14),
        "domain": "science",
        "aliases": ["Einstein"],
        "tags": ["science", "innovation"],
    },
    {
        "name": "Marie Curie",
        "birth_date": date(1867, 11, 7),
        "domain": "science",
        "aliases": ["Maria Sklodowska-Curie", "Madame Curie"],
        "tags": ["science", "innovation"],
    },
    {
        "name": "Richard Branson",
        "birth_date": date(1950, 7, 18),
        "domain": "business",
        "aliases": ["Sir Richard Branson"],
        "tags": ["business", "entrepreneurship", "space", "innovation"],
    },
]


async def seed_database():
    """Seed the database with sample data."""
    async with async_session_maker() as session:
        # Check if data already exists
        result = await session.execute(select(Idol).limit(1))
        if result.scalar_one_or_none():
            print("Database already seeded. Skipping...")
            return

        print("Seeding database...")

        # Create tags
        tags_map: dict[str, IdolTag] = {}
        for tag_data in TAGS_DATA:
            tag = IdolTag(name=tag_data["name"], type=tag_data["type"])
            session.add(tag)
            tags_map[tag_data["name"]] = tag
        
        await session.flush()
        print(f"Created {len(TAGS_DATA)} tags")

        # Create idols with aliases and tag links
        for idol_data in IDOLS_DATA:
            idol = Idol(
                name=idol_data["name"],
                birth_date=idol_data["birth_date"],
                domain=idol_data["domain"],
            )
            session.add(idol)
            await session.flush()

            # Add aliases
            for alias_text in idol_data["aliases"]:
                alias = IdolAlias(idol_id=idol.id, alias_text=alias_text)
                session.add(alias)

            # Add tag links
            for tag_name in idol_data["tags"]:
                if tag_name in tags_map:
                    link = IdolTagLink(
                        idol_id=idol.id,
                        tag_id=tags_map[tag_name].id,
                        weight=1.0,
                    )
                    session.add(link)

        await session.commit()
        print(f"Created {len(IDOLS_DATA)} idols with aliases and tags")
        print("Seeding complete!")


def main():
    asyncio.run(seed_database())


if __name__ == "__main__":
    main()
