"""
Tests for the jargon guard functionality.

Tests that historical idols (like Hannibal) respond without modern corporate jargon
when asked about modern topics like startups.
"""
import pytest
from unittest.mock import MagicMock

from app.services.chat.responder import (
    _contains_banned_jargon,
    _apply_jargon_guard,
    _infer_domain_type,
    _persona_to_json,
    BANNED_MODERN_JARGON,
    DOMAIN_WORLDVIEW_DEFAULTS,
    DOMAIN_FRAMEWORKS_DEFAULTS,
)


class TestBannedJargonDetection:
    """Tests for jargon detection."""
    
    def test_detects_value_proposition(self):
        """Should detect 'value proposition' as banned jargon."""
        text = "You need to define your value proposition clearly."
        found = _contains_banned_jargon(text, BANNED_MODERN_JARGON)
        assert "value proposition" in found
    
    def test_detects_competitors(self):
        """Should detect 'competitors' as banned jargon."""
        text = "Analyze your competitors first."
        found = _contains_banned_jargon(text, BANNED_MODERN_JARGON)
        assert "competitors" in found
    
    def test_detects_mentors(self):
        """Should detect 'mentor' as banned jargon."""
        text = "Find a mentor who can guide you."
        found = _contains_banned_jargon(text, BANNED_MODERN_JARGON)
        assert "mentor" in found
    
    def test_detects_market_research(self):
        """Should detect 'market research' as banned jargon."""
        text = "Start with market research."
        found = _contains_banned_jargon(text, BANNED_MODERN_JARGON)
        assert "market research" in found
    
    def test_detects_networking(self):
        """Should detect 'networking' as banned jargon."""
        text = "Networking is key to success."
        found = _contains_banned_jargon(text, BANNED_MODERN_JARGON)
        assert "networking" in found
    
    def test_no_false_positives_on_clean_text(self):
        """Should not find jargon in clean historical-style text."""
        text = """
        Before any campaign, I always surveyed the terrain first. 
        Understanding the land, the supply lines, the position of rival forces—
        these are the foundations of victory. Build alliances carefully, 
        test your strategies with small maneuvers before committing your main force.
        """
        found = _contains_banned_jargon(text, BANNED_MODERN_JARGON)
        assert len(found) == 0
    
    def test_case_insensitive(self):
        """Should detect jargon regardless of case."""
        text = "Your VALUE PROPOSITION needs work."
        found = _contains_banned_jargon(text, BANNED_MODERN_JARGON)
        assert "value proposition" in found


class TestDomainInference:
    """Tests for domain type inference."""
    
    def test_military_domain(self):
        """Should infer military domain from military-related terms."""
        assert _infer_domain_type(["military", "strategy"]) == "military"
        assert _infer_domain_type(["war", "leadership"]) == "military"
        assert _infer_domain_type(["general", "commander"]) == "military"
    
    def test_philosophy_domain(self):
        """Should infer philosophy domain."""
        assert _infer_domain_type(["philosophy", "ethics"]) == "philosophy"
        assert _infer_domain_type(["logic", "metaphysics"]) == "philosophy"
    
    def test_science_domain(self):
        """Should infer science domain."""
        assert _infer_domain_type(["science", "physics"]) == "science"
        assert _infer_domain_type(["mathematics", "astronomy"]) == "science"
    
    def test_art_domain(self):
        """Should infer art domain."""
        assert _infer_domain_type(["art", "painting"]) == "art"
        assert _infer_domain_type(["music", "sculpture"]) == "art"
    
    def test_politics_domain(self):
        """Should infer politics domain."""
        assert _infer_domain_type(["politics", "government"]) == "politics"
        assert _infer_domain_type(["diplomacy", "statecraft"]) == "politics"
    
    def test_default_domain(self):
        """Should return default for unrecognized domains."""
        assert _infer_domain_type(["unknown", "other"]) == "default"
        assert _infer_domain_type([]) == "default"
        assert _infer_domain_type(None) == "default"


class TestPersonaJsonWithEraFields:
    """Tests for persona JSON generation with era-aware fields."""
    
    def test_ancient_persona_gets_ban_list(self):
        """Ancient persona should include modern jargon ban list."""
        mock_persona = MagicMock()
        mock_persona.voice_style = "authoritative, strategic"
        mock_persona.principles = ["Know your enemy"]
        mock_persona.dos = ["Be direct"]
        mock_persona.donts = ["Retreat unnecessarily"]
        mock_persona.signature_phrases = ["Victory or death"]
        mock_persona.topics_of_strength = ["military strategy"]
        mock_persona.taboo_topics = []
        mock_persona.era_context = "ancient"
        mock_persona.lexicon_allow = None
        mock_persona.lexicon_ban = None
        mock_persona.worldview_adapter = None
        mock_persona.default_frameworks = None
        
        mock_profile = MagicMock()
        mock_profile.domains = ["military", "strategy"]
        
        import json
        result = json.loads(_persona_to_json(mock_persona, mock_profile))
        
        assert result["era_context"] == "ancient"
        assert "value proposition" in result["lexicon_ban"]
        assert "competitors" in result["lexicon_ban"]
        assert result["worldview_adapter"] is not None
        assert "terrain" in result["worldview_adapter"].get("market", "")
    
    def test_contemporary_persona_no_ban_list(self):
        """Contemporary persona should have empty ban list."""
        mock_persona = MagicMock()
        mock_persona.voice_style = "innovative, direct"
        mock_persona.principles = ["Move fast"]
        mock_persona.dos = ["Iterate"]
        mock_persona.donts = ["Be slow"]
        mock_persona.signature_phrases = ["Ship it"]
        mock_persona.topics_of_strength = ["technology"]
        mock_persona.taboo_topics = []
        mock_persona.era_context = "contemporary"
        mock_persona.lexicon_allow = None
        mock_persona.lexicon_ban = None
        mock_persona.worldview_adapter = None
        mock_persona.default_frameworks = None
        
        import json
        result = json.loads(_persona_to_json(mock_persona, None))
        
        assert result["era_context"] == "contemporary"
        assert result["lexicon_ban"] == []


class TestHannibalStartupScenario:
    """
    Integration test: Hannibal Barca asked about startup advice.
    
    Asserts:
    1. Output does NOT contain banned modern jargon
    2. Output includes at least 1 strategist framework
    3. Output includes at least 2 measurable actions
    """
    
    @pytest.mark.asyncio
    async def test_hannibal_startup_response_no_jargon(self):
        """
        When Hannibal is asked about startups, the response should:
        - NOT contain banned modern jargon
        - Include strategist framework references
        - Include measurable actions
        """
        # Simulated LLM response with some jargon (before jargon guard)
        raw_llm_response = """
        You speak of launching a new venture. This is no different from planning a campaign.

        First, study your terrain—the market you wish to enter. Who are the people you must serve? 
        What are their needs? Before committing your main force, send scouts. Run small tests.
        Interview five potential allies who might benefit from your offering.

        I never engaged a larger force without first understanding their weaknesses. 
        Your rivals are no different. Study them, but do not fear them—focus on your own strengths.

        Here is your seven-day plan:
        1. Days 1-2: Write a one-page campaign brief: your goal, who you serve, why now, your constraints.
        2. Days 3-5: Speak with 5 people who might need your offering. Capture their concerns in 10 points.
        3. Days 6-7: Build the simplest version of your offering and test it with 3 people.

        Note: AI simulation based on public sources; may be inaccurate.
        """
        
        # This response is already good (no jargon), so jargon guard should pass it through
        found_jargon = _contains_banned_jargon(raw_llm_response, BANNED_MODERN_JARGON)
        assert len(found_jargon) == 0, f"Found unexpected jargon: {found_jargon}"
        
        # Check for strategist frameworks
        strategist_keywords = [
            "terrain", "campaign", "scouts", "reconnaissance", "forces",
            "flank", "supply", "alliance", "maneuver", "position", "strategy"
        ]
        has_framework = any(kw in raw_llm_response.lower() for kw in strategist_keywords)
        assert has_framework, "Response should include strategist framework language"
        
        # Check for measurable actions (look for numbered items or specific quantities)
        import re
        action_patterns = [
            r'\d+ people',
            r'\d+ points',
            r'\d+ days',
            r'Days \d+-\d+',
            r'Write a.*brief',
            r'Speak with \d+',
            r'Build.*simplest version',
            r'test it with \d+',
        ]
        action_count = sum(1 for p in action_patterns if re.search(p, raw_llm_response, re.IGNORECASE))
        assert action_count >= 2, f"Response should include at least 2 measurable actions, found {action_count}"
    
    @pytest.mark.asyncio
    async def test_jargon_guard_rewrites_modern_jargon(self):
        """
        Test that jargon guard would rewrite a response with modern jargon.
        """
        # Response with jargon that should be caught
        jargon_response = """
        To succeed with your startup, you need a clear value proposition.
        Research your competitors and understand the market.
        Find a mentor who can guide you. Networking is essential.
        
        Note: AI simulation based on public sources; may be inaccurate.
        """
        
        found_jargon = _contains_banned_jargon(jargon_response, BANNED_MODERN_JARGON)
        
        # Should detect all these terms
        assert "value proposition" in found_jargon
        assert "competitors" in found_jargon
        assert "mentor" in found_jargon
        assert "networking" in found_jargon
    
    @pytest.mark.asyncio
    async def test_comparison_generate_jargon_catch(self):
        """Test jargon guard catches terms typical in business comparison."""
        jargon_response = "You lack synergy and need a better value proposition."
        found_jargon = _contains_banned_jargon(jargon_response, BANNED_MODERN_JARGON)
        assert "synergy" in found_jargon
        assert "value proposition" in found_jargon

    @pytest.mark.asyncio
    async def test_blueprint_generate_jargon_catch(self):
        """Test jargon guard catches terms typical in career blueprinting."""
        jargon_response = "Quarter 1: Focus on networking with a mentor."
        found_jargon = _contains_banned_jargon(jargon_response, BANNED_MODERN_JARGON)
        assert "networking" in found_jargon
        assert "mentor" in found_jargon
    
    @pytest.mark.asyncio
    async def test_apply_jargon_guard_skips_modern(self):
        """Jargon guard should skip modern/contemporary idols."""
        text_with_jargon = "Your value proposition needs work. Network more."
        
        # For contemporary era, should return unchanged
        result = await _apply_jargon_guard(
            reply=text_with_jargon,
            era_context="contemporary",
            worldview_adapter={},
            idol_name="Elon Musk",
            domain_type="default",
        )
        
        assert result == text_with_jargon  # Unchanged for modern figures
    
    @pytest.mark.asyncio
    async def test_apply_jargon_guard_processes_ancient(self):
        """Jargon guard should process ancient idols."""
        clean_text = "Study your terrain carefully before advancing."
        
        # For ancient era with no jargon, should return unchanged
        result = await _apply_jargon_guard(
            reply=clean_text,
            era_context="ancient",
            worldview_adapter=DOMAIN_WORLDVIEW_DEFAULTS["military"],
            idol_name="Hannibal Barca",
            domain_type="military",
        )
        
        assert result == clean_text  # No jargon to rewrite


class TestWorldviewDefaults:
    """Test that worldview defaults are properly defined."""
    
    def test_military_worldview_has_required_mappings(self):
        """Military worldview should map modern business terms."""
        wv = DOMAIN_WORLDVIEW_DEFAULTS["military"]
        assert "startup" in wv
        assert "customers" in wv
        assert "market" in wv
        assert "competitors" in wv
        assert wv["market"] == "terrain"
        assert "rival" in wv["competitors"].lower()
    
    def test_all_domains_have_worldviews(self):
        """All domain types should have worldview mappings."""
        required_domains = ["military", "philosophy", "science", "art", "politics", "default"]
        for domain in required_domains:
            assert domain in DOMAIN_WORLDVIEW_DEFAULTS
            assert len(DOMAIN_WORLDVIEW_DEFAULTS[domain]) >= 5


class TestFrameworkDefaults:
    """Test that framework defaults are properly defined."""
    
    def test_military_frameworks(self):
        """Military domain should have strategist frameworks."""
        frameworks = DOMAIN_FRAMEWORKS_DEFAULTS["military"]
        assert len(frameworks) >= 3
        framework_text = " ".join(frameworks).lower()
        assert any(kw in framework_text for kw in ["terrain", "force", "supply", "alliance", "deception"])
    
    def test_all_domains_have_frameworks(self):
        """All domain types should have framework defaults."""
        required_domains = ["military", "philosophy", "science", "art", "politics", "default"]
        for domain in required_domains:
            assert domain in DOMAIN_FRAMEWORKS_DEFAULTS
            assert len(DOMAIN_FRAMEWORKS_DEFAULTS[domain]) >= 3
