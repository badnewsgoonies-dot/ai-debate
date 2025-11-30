#!/usr/bin/env python3
"""
PATTERN 2: GENETIC PROGRAMMING with Fitness Function
Evolves code to solve a problem using evolutionary operators.

Why this matters for AI agents:
- Automatically discover solutions through iteration
- Use test results as fitness metric (objective)
- LLMs can be mutation/crossover operators
"""

import json
import subprocess
import sys
from pathlib import Path

# Target problem: Create a function that correctly implements fizzbuzz
GENERATION_DIR = Path("/tmp/genetic_programming_gen")
GENERATION_DIR.mkdir(exist_ok=True)

FITNESS_TESTS = [
    (1, "1"),
    (3, "Fizz"),
    (5, "Buzz"),
    (15, "FizzBuzz"),
    (7, "7"),
    (9, "Fizz"),
    (10, "Buzz"),
    (30, "FizzBuzz"),
]

def evaluate_fitness(code: str) -> float:
    """
    Fitness function: How many test cases does this code pass?
    Returns: 0.0 (perfect) to 1.0 (total failure)
    """
    test_file = GENERATION_DIR / "candidate.py"
    test_file.write_text(code)

    failures = 0
    for input_val, expected in FITNESS_TESTS:
        try:
            result = subprocess.run(
                [sys.executable, str(test_file), str(input_val)],
                capture_output=True,
                text=True,
                timeout=1
            )
            actual = result.stdout.strip()
            if actual != expected:
                failures += 1
        except (subprocess.TimeoutExpired, Exception):
            failures += 1

    return failures / len(FITNESS_TESTS)

def llm_mutate(code: str, fitness: float) -> str:
    """Use LLM to mutate code based on fitness"""
    prompt = f"""Here is a Python program that takes one integer argument and should implement FizzBuzz:
- Print "Fizz" if divisible by 3
- Print "Buzz" if divisible by 5
- Print "FizzBuzz" if divisible by both
- Otherwise print the number

Current code:
```python
{code}
```

Current fitness (error rate): {fitness:.1%} of tests failing

Output ONLY valid Python code that improves this solution. No explanations."""

    result = subprocess.run(
        ["claude", "-p", prompt],
        capture_output=True,
        text=True
    )

    # Extract code from potential markdown blocks
    output = result.stdout
    if "```python" in output:
        output = output.split("```python")[1].split("```")[0]
    elif "```" in output:
        output = output.split("```")[1].split("```")[0]

    return output.strip()

def main():
    population_size = 3
    generations = 5

    # Initial population (random/simple programs)
    population = [
        "import sys\nprint(sys.argv[1])",  # Just echo
        "import sys\nprint('Fizz')",       # Always Fizz
        "import sys\nn=int(sys.argv[1])\nprint('FizzBuzz' if n%15==0 else 'Fizz' if n%3==0 else 'Buzz' if n%5==0 else str(n))"  # Near-solution
    ]

    print("=== GENETIC PROGRAMMING: FizzBuzz Evolution ===\n")

    for gen in range(generations):
        print(f"Generation {gen + 1}")
        print("-" * 60)

        # Evaluate fitness
        fitness_scores = [(code, evaluate_fitness(code)) for code in population]
        fitness_scores.sort(key=lambda x: x[1])  # Best first

        for i, (code, fitness) in enumerate(fitness_scores):
            status = "✓ PERFECT" if fitness == 0 else f"✗ {fitness:.0%} error"
            print(f"  Candidate {i+1}: {status}")

        best_code, best_fitness = fitness_scores[0]

        if best_fitness == 0:
            print(f"\n🎯 Solution found in generation {gen + 1}!")
            print("\nFinal code:")
            print(best_code)
            return

        # Selection: Keep best, evolve worst
        print(f"  → Evolving worst candidates via LLM mutation...")

        new_population = [best_code]  # Elitism

        # Mutate the rest
        for code, fitness in fitness_scores[1:]:
            if len(new_population) < population_size:
                mutated = llm_mutate(code, fitness)
                new_population.append(mutated)

        population = new_population
        print()

    print("Evolution complete. Best solution:")
    print(population[0])

if __name__ == "__main__":
    main()
