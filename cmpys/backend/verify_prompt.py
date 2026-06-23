import asyncio
import os
import sys

# Add backend to path
sys.path.append(os.path.join(os.getcwd(), "app"))

from app.services.llm.prompt_loader import load_prompt, render_prompt

async def test_comparison_prompt():
    print("Testing comparison prompt rendering...")
    try:
        template = load_prompt("comparison_analyze")
        print("✅ Template loaded.")
        
        # Test render with empty user data
        prompt = render_prompt(template, {
            "idol_name": "Steve Jobs",
            "idol_field": "Technology",
            "target_age": "25",
            "user_age": "25",
            "user_background": "Student",
            "user_achievements": "No achievements recorded.",
            "idol_milestones": "- Founded Apple\n- Launched Apple II",
            "idol_bio": "Visionary entrepreneur."
        }, prompt_name="comparison_analyze.txt", strict=False)
        
        print("✅ Prompt rendered successfully.")
        print("-" * 50)
        print(prompt[:500] + "...")
        print("-" * 50)
        
        if "{{idol_name}}" in prompt:
            print("❌ FAILURE: {{idol_name}} placeholder not replaced!")
        else:
            print("✅ SUCCESS: {{idol_name}} replaced.")
            
        if "NO DATA = 0 SCORE" in prompt:
             print("✅ SUCCESS: Scoring rule present.")
        else:
             print("❌ FAILURE: Scoring rule missing.")

    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    asyncio.run(test_comparison_prompt())
