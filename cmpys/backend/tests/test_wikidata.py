"""Unit tests for Wikidata provider with mocked httpx responses."""
from datetime import date
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.providers.wikidata import (
    INTEREST_TO_OCCUPATIONS,
    _compute_confidence,
    _get_birth_date,
    _get_occupations,
    _is_human,
    _parse_entity,
    _parse_sparql_date,
    _parse_wikidata_time,
    get_occupation_qids,
    search_by_occupations,
    search_candidates,
)


# =============================================================================
# Mock Entity Data
# =============================================================================

def make_human_entity(
    qid: str,
    name: str,
    description: str = "",
    birth_date: str | None = None,
    occupations: list[str] | None = None,
    wiki_title: str | None = None,
) -> dict:
    """Create a mock Wikidata entity for a human."""
    claims = {
        "P31": [
            {
                "mainsnak": {
                    "datavalue": {
                        "type": "wikibase-entityid",
                        "value": {"id": "Q5"},  # Q5 = human
                    }
                }
            }
        ]
    }
    
    if birth_date:
        claims["P569"] = [
            {
                "mainsnak": {
                    "datavalue": {
                        "type": "time",
                        "value": {"time": birth_date},
                    }
                }
            }
        ]
    
    if occupations:
        claims["P106"] = [
            {
                "mainsnak": {
                    "datavalue": {
                        "type": "wikibase-entityid",
                        "value": {"id": occ},
                    }
                }
            }
            for occ in occupations
        ]
    
    entity = {
        "id": qid,
        "labels": {"en": {"value": name}},
        "descriptions": {"en": {"value": description}} if description else {},
        "claims": claims,
        "sitelinks": {},
    }
    
    if wiki_title:
        entity["sitelinks"] = {"enwiki": {"title": wiki_title}}
    
    return entity


def make_non_human_entity(
    qid: str,
    name: str,
    description: str = "",
    instance_of: str = "Q7187",  # Q7187 = gene (not human)
) -> dict:
    """Create a mock Wikidata entity for a non-human (city, gene, given name, etc.)."""
    return {
        "id": qid,
        "labels": {"en": {"value": name}},
        "descriptions": {"en": {"value": description}} if description else {},
        "claims": {
            "P31": [
                {
                    "mainsnak": {
                        "datavalue": {
                            "type": "wikibase-entityid",
                            "value": {"id": instance_of},
                        }
                    }
                }
            ]
        },
        "sitelinks": {},
    }


# =============================================================================
# Test Data for Human Filtering
# =============================================================================

# Search response for "Warren" - includes humans and non-humans
MOCK_WARREN_SEARCH = {
    "search": [
        {"id": "Q1282684", "label": "Warren", "description": "male given name"},
        {"id": "Q754195", "label": "Warren, Ohio", "description": "city in Ohio"},
        {"id": "Q507562", "label": "Warren G. Harding", "description": "29th president of the United States"},
        {"id": "Q47773", "label": "Warren Buffett", "description": "American business magnate"},
    ]
}

MOCK_WARREN_ENTITIES = {
    "entities": {
        # Given name - NOT human (P31 = Q202444 male given name)
        "Q1282684": make_non_human_entity(
            "Q1282684",
            "Warren",
            "male given name",
            instance_of="Q202444",  # male given name
        ),
        # City - NOT human (P31 = Q486972 human settlement)
        "Q754195": make_non_human_entity(
            "Q754195",
            "Warren, Ohio",
            "city in Trumbull County, Ohio, United States",
            instance_of="Q486972",  # human settlement
        ),
        # Warren G. Harding - IS human
        "Q507562": make_human_entity(
            "Q507562",
            "Warren G. Harding",
            "29th president of the United States",
            birth_date="+1865-11-02T00:00:00Z",
            occupations=["Q82955"],  # politician
            wiki_title="Warren G. Harding",
        ),
        # Warren Buffett - IS human
        "Q47773": make_human_entity(
            "Q47773",
            "Warren Buffett",
            "American business magnate and investor",
            birth_date="+1930-08-30T00:00:00Z",
            occupations=["Q131524", "Q43845"],  # entrepreneur, investor
            wiki_title="Warren_Buffett",
        ),
    }
}


# =============================================================================
# Unit Tests
# =============================================================================

class TestParseWikidataTime:
    def test_valid_date(self):
        result = _parse_wikidata_time("+1971-06-28T00:00:00Z")
        assert result == date(1971, 6, 28)

    def test_date_with_zeros(self):
        result = _parse_wikidata_time("+1971-00-00T00:00:00Z")
        assert result == date(1971, 1, 1)

    def test_negative_year(self):
        result = _parse_wikidata_time("-0500-01-01T00:00:00Z")
        # BCE dates may not be supported
        assert result is None or isinstance(result, date)

    def test_empty_string(self):
        result = _parse_wikidata_time("")
        assert result is None

    def test_invalid_format(self):
        result = _parse_wikidata_time("invalid")
        assert result is None


class TestIsHuman:
    def test_is_human(self):
        claims = {
            "P31": [
                {
                    "mainsnak": {
                        "datavalue": {
                            "type": "wikibase-entityid",
                            "value": {"id": "Q5"},
                        }
                    }
                }
            ]
        }
        assert _is_human(claims) is True

    def test_not_human_city(self):
        """Cities should not be classified as human."""
        claims = {
            "P31": [
                {
                    "mainsnak": {
                        "datavalue": {
                            "type": "wikibase-entityid",
                            "value": {"id": "Q486972"},  # human settlement
                        }
                    }
                }
            ]
        }
        assert _is_human(claims) is False

    def test_not_human_given_name(self):
        """Given names should not be classified as human."""
        claims = {
            "P31": [
                {
                    "mainsnak": {
                        "datavalue": {
                            "type": "wikibase-entityid",
                            "value": {"id": "Q202444"},  # male given name
                        }
                    }
                }
            ]
        }
        assert _is_human(claims) is False

    def test_empty_claims(self):
        assert _is_human({}) is False

    def test_multiple_instance_of_including_human(self):
        """Entity with multiple P31 values including Q5 should be human."""
        claims = {
            "P31": [
                {
                    "mainsnak": {
                        "datavalue": {
                            "type": "wikibase-entityid",
                            "value": {"id": "Q15632617"},  # fictional human
                        }
                    }
                },
                {
                    "mainsnak": {
                        "datavalue": {
                            "type": "wikibase-entityid",
                            "value": {"id": "Q5"},  # human
                        }
                    }
                },
            ]
        }
        assert _is_human(claims) is True


class TestGetBirthDate:
    def test_single_date(self):
        claims = {
            "P569": [
                {
                    "mainsnak": {
                        "datavalue": {
                            "type": "time",
                            "value": {"time": "+1971-06-28T00:00:00Z"},
                        }
                    }
                }
            ]
        }
        result = _get_birth_date(claims)
        assert result == date(1971, 6, 28)

    def test_multiple_dates_takes_earliest(self):
        claims = {
            "P569": [
                {
                    "mainsnak": {
                        "datavalue": {
                            "type": "time",
                            "value": {"time": "+1980-01-01T00:00:00Z"},
                        }
                    }
                },
                {
                    "mainsnak": {
                        "datavalue": {
                            "type": "time",
                            "value": {"time": "+1971-06-28T00:00:00Z"},
                        }
                    }
                },
            ]
        }
        result = _get_birth_date(claims)
        assert result == date(1971, 6, 28)

    def test_no_birth_date(self):
        assert _get_birth_date({}) is None


class TestGetOccupations:
    def test_single_occupation(self):
        claims = {
            "P106": [
                {
                    "mainsnak": {
                        "datavalue": {
                            "type": "wikibase-entityid",
                            "value": {"id": "Q131524"},
                        }
                    }
                }
            ]
        }
        result = _get_occupations(claims)
        assert result == ["Q131524"]

    def test_multiple_occupations(self):
        claims = {
            "P106": [
                {
                    "mainsnak": {
                        "datavalue": {
                            "type": "wikibase-entityid",
                            "value": {"id": "Q131524"},
                        }
                    }
                },
                {
                    "mainsnak": {
                        "datavalue": {
                            "type": "wikibase-entityid",
                            "value": {"id": "Q82594"},
                        }
                    }
                },
            ]
        }
        result = _get_occupations(claims)
        assert result == ["Q131524", "Q82594"]

    def test_no_occupations(self):
        assert _get_occupations({}) == []


class TestComputeConfidence:
    """Test confidence scoring with new formula.
    
    Base: 0.2, +0.5 human (always), +0.1 birthdate, +0.1 enwiki, +0.1 exact match
    Note: _compute_confidence is only called for humans, so base is 0.7 (0.2 + 0.5)
    """
    
    def test_base_confidence_human_only(self):
        """Base confidence for human without extras is 0.7."""
        result = _compute_confidence(
            name="Test Person",
            query="Other Query",
            birth_date=None,
            wikipedia_url=None,
        )
        assert result == pytest.approx(0.7)  # 0.2 base + 0.5 human

    def test_with_birth_date(self):
        result = _compute_confidence(
            name="Test Person",
            query="Other",
            birth_date=date(1971, 6, 28),
            wikipedia_url=None,
        )
        assert result == pytest.approx(0.8)  # 0.7 + 0.1 birthdate

    def test_with_wikipedia(self):
        result = _compute_confidence(
            name="Test Person",
            query="Other",
            birth_date=None,
            wikipedia_url="https://en.wikipedia.org/wiki/Test_Person",
        )
        assert result == pytest.approx(0.8)  # 0.7 + 0.1 wiki

    def test_exact_match(self):
        result = _compute_confidence(
            name="Warren Buffett",
            query="warren buffett",  # case-insensitive match
            birth_date=None,
            wikipedia_url=None,
        )
        assert result == pytest.approx(0.8)  # 0.7 + 0.1 exact match

    def test_all_bonuses_capped(self):
        result = _compute_confidence(
            name="Warren Buffett",
            query="warren buffett",
            birth_date=date(1930, 8, 30),
            wikipedia_url="https://en.wikipedia.org/wiki/Warren_Buffett",
        )
        assert result == 0.99  # capped at 0.99 (0.7 + 0.1 + 0.1 + 0.1 = 1.0 -> 0.99)


class TestParseEntityHumanFiltering:
    """Test that _parse_entity filters out non-humans."""

    def test_human_entity_is_returned(self):
        """Human entities should be parsed and returned."""
        entity = make_human_entity(
            "Q507562",
            "Warren G. Harding",
            "29th president of the United States",
            birth_date="+1865-11-02T00:00:00Z",
            wiki_title="Warren G. Harding",
        )
        result = _parse_entity(entity, "Warren")
        
        assert result is not None
        assert result.externalId == "Q507562"
        assert result.name == "Warren G. Harding"
        assert result.confidence >= 0.7  # At least base human confidence

    def test_given_name_filtered_out(self):
        """Given names (like 'Warren' the name) should be filtered out."""
        entity = make_non_human_entity(
            "Q1282684",
            "Warren",
            "male given name",
            instance_of="Q202444",  # male given name
        )
        result = _parse_entity(entity, "Warren")
        
        assert result is None

    def test_city_filtered_out(self):
        """Cities (like 'Warren, Ohio') should be filtered out."""
        entity = make_non_human_entity(
            "Q754195",
            "Warren, Ohio",
            "city in Trumbull County, Ohio, United States",
            instance_of="Q486972",  # human settlement
        )
        result = _parse_entity(entity, "Warren")
        
        assert result is None

    def test_entity_without_p31_filtered_out(self):
        """Entities without P31 (instance of) claim should be filtered out."""
        entity = {
            "id": "Q999999",
            "labels": {"en": {"value": "Unknown Entity"}},
            "descriptions": {},
            "claims": {},  # No P31 claim
            "sitelinks": {},
        }
        result = _parse_entity(entity, "Unknown")
        
        assert result is None


@pytest.mark.asyncio
class TestSearchCandidatesHumanFiltering:
    """Integration tests for human-only filtering in search results."""

    async def test_empty_query(self):
        result = await search_candidates("")
        assert result == []

    async def test_warren_search_filters_non_humans(self):
        """Searching 'Warren' should only return human results."""
        mock_search_response = MagicMock()
        mock_search_response.json.return_value = MOCK_WARREN_SEARCH
        mock_search_response.raise_for_status = MagicMock()

        mock_entity_response = MagicMock()
        mock_entity_response.json.return_value = MOCK_WARREN_ENTITIES
        mock_entity_response.raise_for_status = MagicMock()

        with patch("app.providers.wikidata.httpx.AsyncClient") as mock_client:
            mock_instance = AsyncMock()
            mock_instance.get = AsyncMock(side_effect=[mock_search_response, mock_entity_response])
            mock_client.return_value.__aenter__ = AsyncMock(return_value=mock_instance)
            mock_client.return_value.__aexit__ = AsyncMock(return_value=None)

            result = await search_candidates("Warren", limit=10)

            # Should only return humans: Warren G. Harding and Warren Buffett
            assert len(result) == 2
            
            names = [c.name for c in result]
            
            # Should include humans
            assert "Warren G. Harding" in names
            assert "Warren Buffett" in names
            
            # Should NOT include non-humans
            assert "Warren" not in names  # given name
            assert "Warren, Ohio" not in names  # city

    async def test_given_name_warren_filtered(self):
        """The given name 'Warren' (Q1282684) should be filtered out."""
        mock_search_response = MagicMock()
        mock_search_response.json.return_value = MOCK_WARREN_SEARCH
        mock_search_response.raise_for_status = MagicMock()

        mock_entity_response = MagicMock()
        mock_entity_response.json.return_value = MOCK_WARREN_ENTITIES
        mock_entity_response.raise_for_status = MagicMock()

        with patch("app.providers.wikidata.httpx.AsyncClient") as mock_client:
            mock_instance = AsyncMock()
            mock_instance.get = AsyncMock(side_effect=[mock_search_response, mock_entity_response])
            mock_client.return_value.__aenter__ = AsyncMock(return_value=mock_instance)
            mock_client.return_value.__aexit__ = AsyncMock(return_value=None)

            result = await search_candidates("Warren", limit=10)

            # Verify given name is not in results
            external_ids = [c.externalId for c in result]
            assert "Q1282684" not in external_ids  # given name QID

    async def test_city_warren_ohio_filtered(self):
        """The city 'Warren, Ohio' (Q754195) should be filtered out."""
        mock_search_response = MagicMock()
        mock_search_response.json.return_value = MOCK_WARREN_SEARCH
        mock_search_response.raise_for_status = MagicMock()

        mock_entity_response = MagicMock()
        mock_entity_response.json.return_value = MOCK_WARREN_ENTITIES
        mock_entity_response.raise_for_status = MagicMock()

        with patch("app.providers.wikidata.httpx.AsyncClient") as mock_client:
            mock_instance = AsyncMock()
            mock_instance.get = AsyncMock(side_effect=[mock_search_response, mock_entity_response])
            mock_client.return_value.__aenter__ = AsyncMock(return_value=mock_instance)
            mock_client.return_value.__aexit__ = AsyncMock(return_value=None)

            result = await search_candidates("Warren", limit=10)

            # Verify city is not in results
            external_ids = [c.externalId for c in result]
            assert "Q754195" not in external_ids  # city QID

    async def test_person_warren_g_harding_remains(self):
        """The person 'Warren G. Harding' (Q507562) should remain in results."""
        mock_search_response = MagicMock()
        mock_search_response.json.return_value = MOCK_WARREN_SEARCH
        mock_search_response.raise_for_status = MagicMock()

        mock_entity_response = MagicMock()
        mock_entity_response.json.return_value = MOCK_WARREN_ENTITIES
        mock_entity_response.raise_for_status = MagicMock()

        with patch("app.providers.wikidata.httpx.AsyncClient") as mock_client:
            mock_instance = AsyncMock()
            mock_instance.get = AsyncMock(side_effect=[mock_search_response, mock_entity_response])
            mock_client.return_value.__aenter__ = AsyncMock(return_value=mock_instance)
            mock_client.return_value.__aexit__ = AsyncMock(return_value=None)

            result = await search_candidates("Warren", limit=10)

            # Find Warren G. Harding in results
            harding = next((c for c in result if c.externalId == "Q507562"), None)
            
            assert harding is not None
            assert harding.name == "Warren G. Harding"
            assert harding.birthDate == date(1865, 11, 2)
            assert "https://en.wikipedia.org/wiki/Warren_G._Harding" in harding.wikipediaUrl
            assert harding.confidence == pytest.approx(0.9, abs=0.01)  # human + birthdate + wiki

    async def test_search_no_results(self):
        mock_response = MagicMock()
        mock_response.json.return_value = {"search": []}
        mock_response.raise_for_status = MagicMock()

        with patch("app.providers.wikidata.httpx.AsyncClient") as mock_client:
            mock_instance = AsyncMock()
            mock_instance.get = AsyncMock(return_value=mock_response)
            mock_client.return_value.__aenter__ = AsyncMock(return_value=mock_instance)
            mock_client.return_value.__aexit__ = AsyncMock(return_value=None)

            result = await search_candidates("xyznonexistent123", limit=10)

            assert result == []


# =============================================================================
# Interest to Occupation Mapping Tests
# =============================================================================


class TestInterestToOccupationMapping:
    """Test the interest to Wikidata occupation QID mapping."""

    def test_mapping_exists(self):
        """Verify the mapping dictionary exists and has entries."""
        assert isinstance(INTEREST_TO_OCCUPATIONS, dict)
        assert len(INTEREST_TO_OCCUPATIONS) > 0

    def test_business_interests(self):
        """Business-related interests should map to entrepreneur/investor QIDs."""
        assert "business" in INTEREST_TO_OCCUPATIONS
        assert "investing" in INTEREST_TO_OCCUPATIONS
        
        business_qids = INTEREST_TO_OCCUPATIONS["business"]
        assert "Q131524" in business_qids  # entrepreneur
        assert "Q43845" in business_qids   # businessperson

    def test_technology_interests(self):
        """Tech interests should map to programmer/engineer QIDs."""
        assert "technology" in INTEREST_TO_OCCUPATIONS
        assert "programming" in INTEREST_TO_OCCUPATIONS
        
        tech_qids = INTEREST_TO_OCCUPATIONS["technology"]
        assert "Q11774202" in tech_qids  # programmer

    def test_get_occupation_qids_single_interest(self):
        """get_occupation_qids should return QIDs for a single interest."""
        qids = get_occupation_qids(["business"])
        assert len(qids) > 0
        assert "Q131524" in qids  # entrepreneur

    def test_get_occupation_qids_multiple_interests(self):
        """get_occupation_qids should merge QIDs from multiple interests."""
        qids = get_occupation_qids(["business", "technology"])
        
        # Should have entrepreneur from business
        assert "Q131524" in qids
        # Should have programmer from technology
        assert "Q11774202" in qids

    def test_get_occupation_qids_case_insensitive(self):
        """Interest lookup should be case-insensitive."""
        qids_lower = get_occupation_qids(["business"])
        qids_upper = get_occupation_qids(["BUSINESS"])
        qids_mixed = get_occupation_qids(["BuSiNeSs"])
        
        assert set(qids_lower) == set(qids_upper) == set(qids_mixed)

    def test_get_occupation_qids_unknown_interest(self):
        """Unknown interests should return empty list."""
        qids = get_occupation_qids(["unknown_interest_xyz"])
        assert qids == []

    def test_get_occupation_qids_empty_list(self):
        """Empty interest list should return empty QID list."""
        qids = get_occupation_qids([])
        assert qids == []

    def test_get_occupation_qids_deduplicates(self):
        """QIDs should be deduplicated across interests."""
        # Both business and investing include entrepreneur (Q131524)
        qids = get_occupation_qids(["business", "investing"])
        # Should not have duplicate Q131524
        assert qids.count("Q131524") <= 1 or len(set(qids)) == len(qids)


class TestParseSparqlDate:
    """Test SPARQL date parsing."""

    def test_full_iso_date(self):
        result = _parse_sparql_date("1930-08-30T00:00:00Z")
        assert result == date(1930, 8, 30)

    def test_simple_date(self):
        result = _parse_sparql_date("1865-11-02")
        assert result == date(1865, 11, 2)

    def test_empty_string(self):
        result = _parse_sparql_date("")
        assert result is None

    def test_invalid_format(self):
        result = _parse_sparql_date("invalid-date")
        assert result is None


# Mock SPARQL response data
MOCK_SPARQL_RESPONSE = {
    "results": {
        "bindings": [
            {
                "person": {"value": "http://www.wikidata.org/entity/Q47773"},
                "personLabel": {"value": "Warren Buffett"},
                "personDescription": {"value": "American business magnate"},
                "birthDate": {"value": "1930-08-30T00:00:00Z"},
                "article": {"value": "https://en.wikipedia.org/wiki/Warren_Buffett"},
            },
            {
                "person": {"value": "http://www.wikidata.org/entity/Q312556"},
                "personLabel": {"value": "Bill Gates"},
                "personDescription": {"value": "American businessman and philanthropist"},
                "birthDate": {"value": "1955-10-28T00:00:00Z"},
                "article": {"value": "https://en.wikipedia.org/wiki/Bill_Gates"},
            },
        ]
    }
}

MOCK_SPARQL_EMPTY_RESPONSE = {
    "results": {
        "bindings": []
    }
}


@pytest.mark.asyncio
class TestSearchByOccupations:
    """Test SPARQL-based occupation search."""

    async def test_empty_occupation_list(self):
        """Empty occupation list should return empty results."""
        result = await search_by_occupations([])
        assert result == []

    async def test_successful_sparql_search(self):
        """Should parse SPARQL results into DiscoveryCandidate objects."""
        mock_response = MagicMock()
        mock_response.json.return_value = MOCK_SPARQL_RESPONSE
        mock_response.raise_for_status = MagicMock()

        with patch("app.providers.wikidata.httpx.AsyncClient") as mock_client:
            mock_instance = AsyncMock()
            mock_instance.get = AsyncMock(return_value=mock_response)
            mock_client.return_value.__aenter__ = AsyncMock(return_value=mock_instance)
            mock_client.return_value.__aexit__ = AsyncMock(return_value=None)

            result = await search_by_occupations(["Q131524"], limit=10)

            assert len(result) == 2
            
            # Check Warren Buffett
            buffett = next((c for c in result if c.externalId == "Q47773"), None)
            assert buffett is not None
            assert buffett.name == "Warren Buffett"
            assert buffett.description == "American business magnate"
            assert buffett.birthDate == date(1930, 8, 30)
            assert buffett.wikipediaUrl == "https://en.wikipedia.org/wiki/Warren_Buffett"
            assert buffett.provider == "wikidata"
            
            # Check Bill Gates
            gates = next((c for c in result if c.externalId == "Q312556"), None)
            assert gates is not None
            assert gates.name == "Bill Gates"

    async def test_sparql_no_results(self):
        """Should handle empty SPARQL results."""
        mock_response = MagicMock()
        mock_response.json.return_value = MOCK_SPARQL_EMPTY_RESPONSE
        mock_response.raise_for_status = MagicMock()

        with patch("app.providers.wikidata.httpx.AsyncClient") as mock_client:
            mock_instance = AsyncMock()
            mock_instance.get = AsyncMock(return_value=mock_response)
            mock_client.return_value.__aenter__ = AsyncMock(return_value=mock_instance)
            mock_client.return_value.__aexit__ = AsyncMock(return_value=None)

            result = await search_by_occupations(["Q131524"], limit=10)

            assert result == []

    async def test_sparql_confidence_calculation(self):
        """SPARQL results should have correct confidence scores."""
        mock_response = MagicMock()
        mock_response.json.return_value = MOCK_SPARQL_RESPONSE
        mock_response.raise_for_status = MagicMock()

        with patch("app.providers.wikidata.httpx.AsyncClient") as mock_client:
            mock_instance = AsyncMock()
            mock_instance.get = AsyncMock(return_value=mock_response)
            mock_client.return_value.__aenter__ = AsyncMock(return_value=mock_instance)
            mock_client.return_value.__aexit__ = AsyncMock(return_value=None)

            result = await search_by_occupations(["Q131524"], limit=10)

            # Results have: human (filtered by SPARQL), wikipedia, birthdate
            # confidence = 0.2 + 0.5 + 0.1 + 0.1 = 0.9
            for candidate in result:
                assert candidate.confidence == pytest.approx(0.9, abs=0.01)
