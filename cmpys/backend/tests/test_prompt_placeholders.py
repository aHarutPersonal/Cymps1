"""
Tests for prompt placeholder validation.

Ensures all prompts receive their required parameters when rendered.
"""
import pytest

from app.services.llm.prompt_loader import (
    PROMPT_PLACEHOLDERS,
    PromptRenderError,
    extract_placeholders,
    get_required_placeholders,
    load_and_render,
    load_prompt,
    render_prompt,
    validate_prompt_params,
)


class TestPlanGeneratePlaceholders:
    """Tests for plan_generate.txt placeholder validation."""

    def test_plan_generate_required_placeholders(self):
        """Verify plan_generate.txt has all required placeholders in registry."""
        required = get_required_placeholders("plan_generate.txt")
        
        expected = [
            "user_goal",
            "idol_name",
            "hours_per_week",
            "user_context",
        ]
        
        for placeholder in expected:
            assert placeholder in required, f"Missing placeholder: {placeholder}"

    def test_plan_generate_render_succeeds_with_all_params(self):
        """Render plan_generate.txt successfully when all params provided."""
        params = {
            "user_goal": "learn finance",
            "idol_name": "Warren Buffett",
            "hours_per_week": "10",
            "user_context": "beginner in investing",
        }
        
        # Should not raise
        rendered = load_and_render("plan_generate", params, strict=True)
        
        # Verify key content is in the rendered prompt
        assert "learn finance" in rendered
        assert "Warren Buffett" in rendered
        assert "beginner in investing" in rendered

    def test_plan_generate_render_fails_without_required_params(self):
        """Fail when required placeholders are missing."""
        incomplete_params = {
            "idol_name": "Warren Buffett",
            "user_goal": "learn finance",
            # Missing: hours_per_week, user_context
        }
        
        with pytest.raises(PromptRenderError) as exc_info:
            load_and_render("plan_generate", incomplete_params, strict=True)
        
        # Check the error mentions missing params
        assert "hours_per_week" in exc_info.value.missing_keys or \
               "user_context" in exc_info.value.missing_keys

    def test_plan_generate_placeholder_names_match_template(self):
        """Ensure registry placeholders match what's actually in the template."""
        template = load_prompt("plan_generate")
        
        # Extract placeholders from template
        found_in_template = extract_placeholders(template)
        
        # Get registered placeholders
        registered = set(get_required_placeholders("plan_generate.txt"))
        
        # All registered placeholders should be in the template
        for placeholder in registered:
            assert placeholder in found_in_template, \
                f"Registered placeholder '{placeholder}' not found in template"


class TestValidatePromptParams:
    """Tests for validate_prompt_params utility."""

    def test_validate_returns_missing_params(self):
        """Returns list of missing parameters."""
        params = {"idol_name": "Test", "user_goal": "Win"}
        missing = validate_prompt_params("plan_generate", params)
        
        assert "hours_per_week" in missing
        assert "user_context" in missing

    def test_validate_returns_empty_when_all_present(self):
        """Returns empty list when all params provided."""
        params = {
            "user_goal": "Win",
            "idol_name": "Test",
            "hours_per_week": "10",
            "user_context": "",
        }
        missing = validate_prompt_params("plan_generate", params)
        
        assert missing == []


class TestPromptPlaceholderRegistry:
    """Tests for the PROMPT_PLACEHOLDERS registry."""

    def test_all_prompt_files_have_registry_entry(self):
        """Every prompt file in registry should exist."""
        from pathlib import Path
        
        prompts_dir = Path(__file__).parent.parent.parent / "prompts"
        
        for prompt_name in PROMPT_PLACEHOLDERS.keys():
            prompt_path = prompts_dir / prompt_name
            assert prompt_path.exists(), f"Prompt file not found: {prompt_name}"

    def test_registry_has_key_prompts(self):
        """Registry should include all key prompt files."""
        key_prompts = [
            "plan_generate.txt",
            "chat_system.txt",
            "chat_reply.txt",
            "profile_extract.txt",
            "achievements_extract.txt",
            "intake_questions_generate.txt",
            "intake_answers_normalize.txt",
            "interview_system.xml",
            "interview_question.txt",
            "comparison_generate.txt",
            "blueprint_generate.txt",
            "idol_suggest.txt",
        ]
        
        for prompt in key_prompts:
            assert prompt in PROMPT_PLACEHOLDERS, f"Missing registry entry: {prompt}"


class TestRenderPromptJsonHandling:
    """Tests for JSON handling in render_prompt."""

    def test_dict_values_are_json_serialized(self):
        """Dict values should be JSON-serialized automatically."""
        template = "Profile: {profile_json}"
        result = render_prompt(template, {"profile_json": {"name": "Test", "age": 25}})
        
        assert '"name": "Test"' in result
        assert '"age": 25' in result

    def test_list_values_are_json_serialized(self):
        """List values should be JSON-serialized automatically."""
        template = "Items: {items_json}"
        result = render_prompt(template, {"items_json": ["a", "b", "c"]})
        
        assert '["a", "b", "c"]' in result or '[\n  "a"' in result

    def test_none_values_become_null(self):
        """None values should become 'null' string."""
        template = "Value: {value}"
        result = render_prompt(template, {"value": None})
        
        assert "Value: null" in result
