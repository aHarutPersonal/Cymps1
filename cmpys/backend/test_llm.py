import asyncio
from app.services.llm.client import get_llm_client
from app.services.llm.prompt_loader import load_prompt, render_prompt
from app.services.llm.schemas import IdolDiscoverResponse
import json

async def main():
    client = get_llm_client(timeout=60.0, fast=True)
    interest_list = ['finance', 'startups', 'technology', 'leadership', 'innovation']
    
    system_prompt = "You are a knowledge assistant that helps discover notable people as role models. Be concise."
    user_template = load_prompt("idol_discover")
    user_prompt = render_prompt(user_template, {
        "interests_json_array": json.dumps(interest_list),
        "user_age": "null",
        "limit": "20",
    }, prompt_name="idol_discover.txt")
    
    try:
        validated, response = await client.generate_and_validate(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            output_model=IdolDiscoverResponse,
            repair_on_failure=False,
        )
        print(f"Validated: {validated}")
        if validated:
            print(f"Candidates: {len(validated.candidates)}")
    except Exception as e:
        print(f"Error: {e}")

asyncio.run(main())
