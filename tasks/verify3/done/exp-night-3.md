run: echo "experiment 3 running at $(date -u +%Y-%m-%dT%H:%M:%SZ)" && python3 -c "import time; time.sleep(2); print(\"exp 3 compute done\")" && echo "exp 3 complete"
