"""
Wikidata provider for idol discovery.

Uses the Wikidata API to search for entities and fetch their details.
"""
from datetime import date

import httpx

from app.providers.models import DiscoveryCandidate

WIKIDATA_API_URL = "https://www.wikidata.org/w/api.php"
WIKIDATA_SPARQL_URL = "https://query.wikidata.org/sparql"

# Wikimedia APIs require a User-Agent header
# https://meta.wikimedia.org/wiki/User-Agent_policy
HEADERS = {
    "User-Agent": "CMPYS/1.0 (https://github.com/cmpys; contact@cmpys.app) httpx/0.27"
}

# Wikidata property IDs
P_INSTANCE_OF = "P31"
P_DATE_OF_BIRTH = "P569"
P_OCCUPATION = "P106"

# Wikidata entity IDs
Q_HUMAN = "Q5"

# =============================================================================
# Interest to Occupation Mapping
# =============================================================================
# Maps user-friendly interest names to Wikidata occupation QIDs.
# Each interest can map to multiple occupations to broaden search results.
#
# Occupation QIDs reference:
# - Q131524: entrepreneur
# - Q806798: investor  
# - Q43845: businessperson
# - Q82955: politician
# - Q36180: writer/author
# - Q1930187: journalist
# - Q33999: actor
# - Q177220: singer
# - Q639669: musician
# - Q11774202: programmer
# - Q81096: engineer
# - Q901: scientist
# - Q36834: composer
# - Q49757: poet
# - Q482980: author
# - Q15253558: activist
# - Q2259451: philanthropist
# - Q3282637: film producer
# - Q28389: screenwriter
# - Q10800557: film director
# - Q40348: lawyer
# - Q189290: military officer
# - Q39631: physician
# - Q2066131: athlete
# - Q937857: football player
# - Q3665646: basketball player
# - Q10871364: tennis player
# =============================================================================

INTEREST_TO_OCCUPATIONS: dict[str, list[str]] = {
    # Business & Finance
    "business": ["Q131524", "Q43845", "Q806798"],  # entrepreneur, businessperson, investor
    "investing": ["Q806798", "Q43845", "Q131524"],  # investor, businessperson, entrepreneur
    "entrepreneurship": ["Q131524", "Q43845"],  # entrepreneur, businessperson
    "finance": ["Q806798", "Q43845"],  # investor, businessperson
    
    # Tech & Engineering
    "technology": ["Q11774202", "Q81096", "Q131524"],  # programmer, engineer, entrepreneur
    "programming": ["Q11774202"],  # programmer
    "engineering": ["Q81096"],  # engineer
    "science": ["Q901"],  # scientist
    
    # Politics & Leadership
    "politics": ["Q82955"],  # politician
    "leadership": ["Q82955", "Q131524", "Q43845"],  # politician, entrepreneur, businessperson
    "activism": ["Q15253558"],  # activist
    "philanthropy": ["Q2259451"],  # philanthropist
    
    # Arts & Entertainment
    "acting": ["Q33999"],  # actor
    "music": ["Q177220", "Q639669", "Q36834"],  # singer, musician, composer
    "film": ["Q10800557", "Q3282637", "Q28389"],  # film director, producer, screenwriter
    "writing": ["Q36180", "Q482980", "Q49757"],  # writer, author, poet
    "journalism": ["Q1930187"],  # journalist
    
    # Sports
    "sports": ["Q2066131"],  # athlete
    "football": ["Q937857"],  # football player
    "basketball": ["Q3665646"],  # basketball player
    "tennis": ["Q10871364"],  # tennis player
    
    # Professions
    "law": ["Q40348"],  # lawyer
    "medicine": ["Q39631"],  # physician
    "military": ["Q189290"],  # military officer
}


async def fetch_entity_by_id(qid: str) -> dict | None:
    """
    Fetch a single entity by its Wikidata QID.
    
    Returns a dict with name, birth_date, wikipedia_url, or None if not found.
    """
    async with httpx.AsyncClient(timeout=30.0, headers=HEADERS) as client:
        entities_data = await _fetch_entities(client, [qid])
        if not entities_data or qid not in entities_data:
            return None

        entity = entities_data[qid]
        
        # Get label (name)
        labels = entity.get("labels", {})
        name = labels.get("en", {}).get("value")
        if not name:
            return None

        # Parse claims
        claims = entity.get("claims", {})
        birth_date = _get_birth_date(claims)

        # Get Wikipedia URL from sitelinks
        sitelinks = entity.get("sitelinks", {})
        wikipedia_url = None
        if "enwiki" in sitelinks:
            wiki_title = sitelinks["enwiki"].get("title", "")
            if wiki_title:
                wikipedia_url = f"https://en.wikipedia.org/wiki/{wiki_title.replace(' ', '_')}"

        return {
            "name": name,
            "birth_date": birth_date,
            "wikipedia_url": wikipedia_url,
        }


async def search_candidates(query: str, limit: int = 10) -> list[DiscoveryCandidate]:
    """
    Search Wikidata for candidates matching the query.
    
    1. Call wbsearchentities to find matching items
    2. For each QID, fetch detailed entity data
    3. Parse and compute confidence scores
    """
    if not query.strip():
        return []

    async with httpx.AsyncClient(timeout=30.0, headers=HEADERS) as client:
        # Step 1: Search for entities
        qids = await _search_entities(client, query, limit)
        if not qids:
            return []

        # Step 2: Fetch entity details
        entities_data = await _fetch_entities(client, qids)
        if not entities_data:
            return []

        # Step 3: Parse and build candidates
        candidates = []
        for qid in qids:
            if qid in entities_data:
                candidate = _parse_entity(entities_data[qid], query)
                if candidate:
                    candidates.append(candidate)

        return candidates


async def _search_entities(
    client: httpx.AsyncClient, query: str, limit: int
) -> list[str]:
    """Search Wikidata for entities matching the query."""
    params = {
        "action": "wbsearchentities",
        "format": "json",
        "language": "en",
        "uselang": "en",
        "type": "item",
        "search": query,
        "limit": limit,
    }

    response = await client.get(WIKIDATA_API_URL, params=params)
    response.raise_for_status()
    data = response.json()

    return [item["id"] for item in data.get("search", [])]


async def _fetch_entities(
    client: httpx.AsyncClient, qids: list[str]
) -> dict:
    """Fetch detailed entity data for the given QIDs."""
    params = {
        "action": "wbgetentities",
        "format": "json",
        "ids": "|".join(qids),
        "props": "labels|descriptions|claims|sitelinks",
        "languages": "en",
        "sitefilter": "enwiki",
    }

    response = await client.get(WIKIDATA_API_URL, params=params)
    response.raise_for_status()
    data = response.json()

    return data.get("entities", {})


def _parse_entity(entity: dict, query: str) -> DiscoveryCandidate | None:
    """
    Parse a Wikidata entity into a DiscoveryCandidate.
    
    Only returns humans (P31 includes Q5). Non-human entities are filtered out.
    """
    qid = entity.get("id")
    if not qid:
        return None

    # Get label (name)
    labels = entity.get("labels", {})
    name = labels.get("en", {}).get("value")
    if not name:
        return None

    # Parse claims
    claims = entity.get("claims", {})

    # Filter: only return humans (P31 includes Q5)
    if not _is_human(claims):
        return None

    # Get description
    descriptions = entity.get("descriptions", {})
    description = descriptions.get("en", {}).get("value")

    # Get birth date (P569)
    birth_date = _get_birth_date(claims)

    # Get occupations (P106) - returns QIDs for now
    # TODO: Resolve occupation QIDs to human-readable labels
    occupations = _get_occupations(claims)

    # Get Wikipedia URL from sitelinks
    sitelinks = entity.get("sitelinks", {})
    wikipedia_url = None
    if "enwiki" in sitelinks:
        wiki_title = sitelinks["enwiki"].get("title", "")
        if wiki_title:
            wikipedia_url = f"https://en.wikipedia.org/wiki/{wiki_title.replace(' ', '_')}"

    # Compute confidence score
    confidence = _compute_confidence(
        name=name,
        query=query,
        birth_date=birth_date,
        wikipedia_url=wikipedia_url,
    )

    return DiscoveryCandidate(
        provider="wikidata",
        externalId=qid,
        name=name,
        description=description,
        birthDate=birth_date,
        wikipediaUrl=wikipedia_url,
        occupations=occupations,
        confidence=confidence,
    )


def _is_human(claims: dict) -> bool:
    """Check if entity is an instance of human (Q5)."""
    instance_of_claims = claims.get(P_INSTANCE_OF, [])
    for claim in instance_of_claims:
        mainsnak = claim.get("mainsnak", {})
        datavalue = mainsnak.get("datavalue", {})
        if datavalue.get("type") == "wikibase-entityid":
            value = datavalue.get("value", {})
            if value.get("id") == Q_HUMAN:
                return True
    return False


def _get_birth_date(claims: dict) -> date | None:
    """Extract birth date from P569 claim (take earliest)."""
    birth_claims = claims.get(P_DATE_OF_BIRTH, [])
    dates = []

    for claim in birth_claims:
        mainsnak = claim.get("mainsnak", {})
        datavalue = mainsnak.get("datavalue", {})
        if datavalue.get("type") == "time":
            time_value = datavalue.get("value", {})
            time_str = time_value.get("time", "")
            parsed_date = _parse_wikidata_time(time_str)
            if parsed_date:
                dates.append(parsed_date)

    if dates:
        return min(dates)
    return None


def _parse_wikidata_time(time_str: str) -> date | None:
    """
    Parse Wikidata time format.
    Format: +YYYY-MM-DDT00:00:00Z or -YYYY-MM-DDT00:00:00Z
    """
    if not time_str:
        return None

    try:
        # Remove leading + or -
        if time_str.startswith("+") or time_str.startswith("-"):
            time_str = time_str[1:]

        # Extract date part
        date_part = time_str.split("T")[0]
        parts = date_part.split("-")

        if len(parts) >= 3:
            year = int(parts[0])
            month = int(parts[1]) if int(parts[1]) > 0 else 1
            day = int(parts[2]) if int(parts[2]) > 0 else 1
            return date(year, month, day)
    except (ValueError, IndexError):
        pass

    return None


def _get_occupations(claims: dict) -> list[str]:
    """
    Extract occupation QIDs from P106 claims.
    
    Returns a list of Wikidata QIDs (e.g., ["Q82955", "Q131524"]).
    TODO: Resolve these QIDs to human-readable labels in a future update.
    """
    occupation_claims = claims.get(P_OCCUPATION, [])
    occupations = []

    for claim in occupation_claims:
        mainsnak = claim.get("mainsnak", {})
        datavalue = mainsnak.get("datavalue", {})
        if datavalue.get("type") == "wikibase-entityid":
            value = datavalue.get("value", {})
            qid = value.get("id")
            if qid:
                occupations.append(qid)

    return occupations


def _compute_confidence(
    name: str,
    query: str,
    birth_date: date | None,
    wikipedia_url: str | None,
) -> float:
    """
    Compute confidence score for a candidate.
    
    Note: Only called for humans (non-humans are filtered out earlier).
    
    Base: 0.2
    +0.5 human (always true since we filter)
    +0.1 if has birthDate
    +0.1 if has enwiki link
    +0.1 if exact label match (case-insensitive)
    Cap at 0.99
    """
    # Base + human bonus (we only call this for humans)
    confidence = 0.2 + 0.5

    # Has birth date
    if birth_date:
        confidence += 0.1

    # Has Wikipedia URL
    if wikipedia_url:
        confidence += 0.1

    # Exact label match (case-insensitive)
    if name.lower() == query.lower():
        confidence += 0.1

    return min(confidence, 0.99)


# =============================================================================
# SPARQL-based Occupation Search
# =============================================================================


def get_occupation_qids(interests: list[str]) -> list[str]:
    """
    Map user interests to Wikidata occupation QIDs.
    
    Args:
        interests: List of interest names (e.g., ["business", "investing"])
        
    Returns:
        List of unique Wikidata QIDs for matching occupations.
    """
    qids = set()
    for interest in interests:
        interest_lower = interest.lower().strip()
        if interest_lower in INTEREST_TO_OCCUPATIONS:
            qids.update(INTEREST_TO_OCCUPATIONS[interest_lower])
    return list(qids)


async def search_by_occupations(
    occupation_qids: list[str],
    limit: int = 20,
) -> list[DiscoveryCandidate]:
    """
    Search Wikidata for humans with specific occupations using SPARQL.
    
    Uses the Wikidata Query Service to find people (P31=Q5) whose
    occupation (P106) matches the given QIDs.
    
    Args:
        occupation_qids: List of Wikidata occupation QIDs (e.g., ["Q131524", "Q806798"])
        limit: Maximum number of results to return
        
    Returns:
        List of DiscoveryCandidate objects with provider="wikidata"
    """
    if not occupation_qids:
        return []

    # Build SPARQL VALUES clause for occupations
    occupation_values = " ".join(f"wd:{qid}" for qid in occupation_qids)
    
    # Optimized SPARQL query - require Wikipedia article and sitelinks for speed
    # This filters to notable people only and runs much faster
    sparql_query = f"""
    SELECT DISTINCT ?person ?personLabel ?personDescription ?birthDate ?article WHERE {{
      VALUES ?occupation {{ {occupation_values} }}
      ?person wdt:P31 wd:Q5 .           # instance of human
      ?person wdt:P106 ?occupation .     # has matching occupation
      ?person wikibase:sitelinks ?sitelinks .  # has sitelinks (notable)
      
      # Require English Wikipedia article for faster results
      ?article schema:about ?person .
      ?article schema:isPartOf <https://en.wikipedia.org/> .
      
      OPTIONAL {{ ?person wdt:P569 ?birthDate . }}
      
      SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en" . }}
    }}
    ORDER BY DESC(?sitelinks)
    LIMIT {limit}
    """
    
    # Use shorter timeout for SPARQL - it's slow by nature
    async with httpx.AsyncClient(timeout=10.0, headers=HEADERS) as client:
        try:
            response = await client.get(
                WIKIDATA_SPARQL_URL,
                params={"query": sparql_query, "format": "json"},
                headers={"Accept": "application/sparql-results+json"},
            )
            response.raise_for_status()
            data = response.json()
        except (httpx.HTTPStatusError, httpx.RequestError, httpx.TimeoutException) as e:
            import logging
            logging.getLogger(__name__).warning(f"SPARQL query failed: {e}")
            return []
    
    candidates = []
    bindings = data.get("results", {}).get("bindings", [])
    seen_qids = set()
    
    for binding in bindings:
        # Extract QID from person URI
        person_uri = binding.get("person", {}).get("value", "")
        if not person_uri:
            continue
        qid = person_uri.split("/")[-1]
        
        # Skip duplicates
        if qid in seen_qids:
            continue
        seen_qids.add(qid)
        
        # Extract name
        name = binding.get("personLabel", {}).get("value", "")
        if not name or name == qid:  # Skip if no label found
            continue
        
        # Extract description
        description = binding.get("personDescription", {}).get("value")
        
        # Extract birth date
        birth_date = None
        birth_str = binding.get("birthDate", {}).get("value", "")
        if birth_str:
            birth_date = _parse_sparql_date(birth_str)
        
        # Extract Wikipedia URL
        wikipedia_url = binding.get("article", {}).get("value")
        
        # Compute confidence - all results have Wikipedia now
        confidence = 0.2 + 0.5 + 0.1  # base + human + wikipedia
        if birth_date:
            confidence += 0.1
        confidence = min(confidence, 0.99)
        
        candidates.append(DiscoveryCandidate(
            provider="wikidata",
            externalId=qid,
            name=name,
            description=description,
            birthDate=birth_date,
            wikipediaUrl=wikipedia_url,
            occupations=occupation_qids,  # All matched occupations
            confidence=confidence,
        ))
    
    return candidates[:limit]


def _parse_sparql_date(date_str: str) -> date | None:
    """
    Parse date from SPARQL result.
    Format: YYYY-MM-DD or full ISO datetime
    """
    if not date_str:
        return None
    
    try:
        # Handle ISO datetime format
        date_part = date_str.split("T")[0]
        parts = date_part.split("-")
        
        if len(parts) >= 3:
            year = int(parts[0])
            month = int(parts[1]) if parts[1] else 1
            day = int(parts[2]) if parts[2] else 1
            
            # Validate reasonable date
            if year > 0 and 1 <= month <= 12 and 1 <= day <= 31:
                return date(year, month, day)
    except (ValueError, IndexError):
        pass
    
    return None
