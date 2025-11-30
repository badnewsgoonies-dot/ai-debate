#!/usr/bin/env python3
"""
PATTERN 4: SKILL LIBRARY (Voyager-style)
Agent writes and stores reusable functions, retrieves them for future tasks.

Why this matters for AI agents:
- Compound capabilities over time
- No catastrophic forgetting (skills persist)
- Compose simple skills into complex behaviors
- Vector search for relevant past solutions
"""

import json
import subprocess
import hashlib
from pathlib import Path
from typing import List, Dict, Any

SKILL_DIR = Path("/tmp/skill_library")
SKILL_INDEX = SKILL_DIR / "index.json"

class SkillLibrary:
    def __init__(self):
        SKILL_DIR.mkdir(exist_ok=True)
        if not SKILL_INDEX.exists():
            SKILL_INDEX.write_text(json.dumps({"skills": []}, indent=2))

    def add_skill(self, description: str, code: str, tags: List[str] = None):
        """Store a new skill"""
        skill_id = hashlib.md5(description.encode()).hexdigest()[:8]
        skill_file = SKILL_DIR / f"skill_{skill_id}.py"

        skill_file.write_text(code)

        # Update index
        index = json.loads(SKILL_INDEX.read_text())
        index["skills"].append({
            "id": skill_id,
            "description": description,
            "file": str(skill_file),
            "tags": tags or [],
            "uses": 0
        })
        SKILL_INDEX.write_text(json.dumps(index, indent=2))

        print(f"✓ Skill added: {skill_id} - {description}")
        return skill_id

    def search_skills(self, query: str, limit: int = 5) -> List[Dict[str, Any]]:
        """Find relevant skills (simple keyword matching, could use embeddings)"""
        index = json.loads(SKILL_INDEX.read_text())

        # Simple relevance: count matching words
        query_words = set(query.lower().split())

        scored_skills = []
        for skill in index["skills"]:
            desc_words = set(skill["description"].lower().split())
            score = len(query_words & desc_words)
            if score > 0:
                scored_skills.append((score, skill))

        scored_skills.sort(reverse=True, key=lambda x: x[0])
        return [skill for _, skill in scored_skills[:limit]]

    def get_skill_code(self, skill_id: str) -> str:
        """Retrieve skill code"""
        index = json.loads(SKILL_INDEX.read_text())
        for skill in index["skills"]:
            if skill["id"] == skill_id:
                return Path(skill["file"]).read_text()
        return None

    def increment_usage(self, skill_id: str):
        """Track skill usage"""
        index = json.loads(SKILL_INDEX.read_text())
        for skill in index["skills"]:
            if skill["id"] == skill_id:
                skill["uses"] += 1
        SKILL_INDEX.write_text(json.dumps(index, indent=2))

    def list_skills(self):
        """Show all skills"""
        index = json.loads(SKILL_INDEX.read_text())
        print(f"\n=== Skill Library ({len(index['skills'])} skills) ===")
        for skill in index["skills"]:
            print(f"  [{skill['id']}] {skill['description']}")
            print(f"     Tags: {', '.join(skill['tags'])} | Uses: {skill['uses']}")


def agent_solve_task(task: str, library: SkillLibrary) -> str:
    """Agent attempts to solve task using skill library + LLM"""

    print(f"\n🎯 Task: {task}")

    # Search for relevant skills
    relevant_skills = library.search_skills(task)

    if relevant_skills:
        print(f"\n📚 Found {len(relevant_skills)} relevant skills:")
        context = "You have access to these previously written skills:\n\n"
        for skill in relevant_skills:
            code = library.get_skill_code(skill["id"])
            context += f"# {skill['description']}\n```python\n{code}\n```\n\n"
            print(f"  - {skill['description']}")
    else:
        print("\n📚 No relevant skills found. Starting from scratch.")
        context = ""

    # Ask LLM to solve (potentially using/composing existing skills)
    prompt = f"""{context}
Task: {task}

Write a Python function that solves this task. If you can use or compose the existing skills above, do so.
Output ONLY the Python code, nothing else."""

    result = subprocess.run(
        ["claude", "-p", prompt],
        capture_output=True,
        text=True
    )

    code = result.stdout.strip()

    # Extract from markdown if present
    if "```python" in code:
        code = code.split("```python")[1].split("```")[0].strip()
    elif "```" in code:
        code = code.split("```")[1].split("```")[0].strip()

    print("\n💻 Generated solution:")
    print(code)

    # Optionally: Test the code, and if successful, add to library
    return code


def demo_workflow():
    """Demonstrate skill library workflow"""

    library = SkillLibrary()

    print("=== SKILL LIBRARY DEMO ===")
    print("Agent will solve tasks and build reusable skills over time.\n")

    # Task 1: Basic skill
    print("\n" + "="*60)
    task1 = "read a JSON file and return its contents as a dict"
    code1 = agent_solve_task(task1, library)

    print("\n💾 Adding to skill library...")
    library.add_skill(task1, code1, tags=["json", "file", "io"])

    # Task 2: Another basic skill
    print("\n" + "="*60)
    task2 = "calculate the average of a list of numbers"
    code2 = agent_solve_task(task2, library)

    print("\n💾 Adding to skill library...")
    library.add_skill(task2, code2, tags=["math", "statistics"])

    # Task 3: Composite task (should find and use previous skills)
    print("\n" + "="*60)
    task3 = "read a JSON file containing a list of numbers and calculate their average"
    code3 = agent_solve_task(task3, library)

    print("\n💾 Adding composite skill...")
    library.add_skill(task3, code3, tags=["json", "math", "composite"])

    # Show library state
    print("\n" + "="*60)
    library.list_skills()

    print("\n✨ The agent now has a growing library of reusable skills!")
    print("Future tasks can compose these building blocks into complex behaviors.")


if __name__ == "__main__":
    demo_workflow()
