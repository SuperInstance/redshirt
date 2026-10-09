run: echo "experiment 4 running at $(date -u +%Y-%m-%dT%H:%M:%SZ)" && python3 -c "import time; time.sleep(2); print(\"exp 4 compute done\")" && echo "exp 4 complete"
