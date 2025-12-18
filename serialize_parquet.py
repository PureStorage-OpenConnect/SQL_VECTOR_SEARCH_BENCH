import pandas as pd
import json
import sys
import os

# CONFIG
DATASET_PATH = "/dataset/test_large.parquet" # Adjust if your file is named differently
OUTPUT_FILE = "vectors_large.jsonl"  

def main():
    if not os.path.exists(DATASET_PATH):
        print(f"Error: Could not find {DATASET_PATH}")
        sys.exit(1)

    print(f"Reading {DATASET_PATH}...")
    df = pd.read_parquet(DATASET_PATH)
    
    print(f"Converting {len(df)} vectors to JSONL format...")
    
    with open(OUTPUT_FILE, 'w') as f:
        for vec in df['emb']:
            # Convert numpy array to list if needed, then to compact JSON string
            if hasattr(vec, 'tolist'):
                vec = vec.tolist()
            # Write one JSON vector per line
            json_str = json.dumps(vec, separators=(',', ':'))
            f.write(json_str + '\n')
            
    print(f"✓ Done! Saved to {OUTPUT_FILE}")
    print("You can now run the Go benchmark.")

if __name__ == "__main__":
    main()
