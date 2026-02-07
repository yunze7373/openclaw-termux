#!/usr/bin/env python3
import sys
import json

def learn_preference(preference_key, preference_value):
    # This is a placeholder script.
    # In a real implementation, this would parse the input,
    # and write the preference to a structured file like JSON or Markdown.
    # For now, it just prints the received preference.
    print(f"Learned preference: {preference_key} = {preference_value}")
    # Future: read existing preferences, update, and write back.

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python learn_preference.py <preference_key> <preference_value>")
        sys.exit(1)
    
    key = sys.argv[1]
    value = sys.argv[2]
    learn_preference(key, value)
