#!/bin/bash
# ==============================================================================
# 8-NODE CLUSTER BENCHMARK - GO EDITION
# 4 Clients -> driving 8 SQL Nodes
# OPTIMIZED: VM4 load reduced (Moved SQL4 -> VM2)
# ==============================================================================

# --- CONFIGURATION ---
REMOTE_USER="root"
REMOTE_PASS="your_remote_clients_password"

REMOTE_BIN="/root/golang/search_engine_v1"
JSONL_FILE="/root/golang/vectors_large.jsonl"
SQL_PWD="Osmium76&"

# --- SQL NODES (8 Nodes) ---
SQL1="10.21.XX.8"
SQL2="10.21.XX.9"
SQL3="10.21.XX.9"
SQL4="10.21.XX.10"
SQL5="10.21.XX.11"
SQL6="10.21.XX.12"
SQL7="10.21.XX.13"
SQL8="10.21.XX.14"

# --- CLIENT VMS ---
CLIENT1="10.21.XX.144"
CLIENT2="10.21.XX.145"
CLIENT3="10.21.XX.143"
CLIENT4="10.21.XX.142"

ALL_CLIENTS="$CLIENT1 $CLIENT2 $CLIENT3 $CLIENT4"

# --- BENCH SETTINGS ---
DURATION=30
# Concurrency: Steps of 10
CONCURRENCY_LIST="10 20 30 40 50 60 70 80 90 100"
TOP_K=10
TOP_N=50

# --- SETUP ---
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="./go_8node_results_${TIMESTAMP}"
mkdir -p "$OUTPUT_DIR"
echo "Concurrency,TotalQPS,AvgP50,AvgP95,AvgP99" > "${OUTPUT_DIR}/summary.csv"

cleanup() {
    echo ""
    echo "🧹 Cleaning up remote processes..."
    for ip in $ALL_CLIENTS; do
        sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no $REMOTE_USER@$ip \
            "pkill -f search_engine_v1" 2>/dev/null &
    done
    wait
}
trap cleanup INT TERM

echo "=========================================================="
echo "🚀 STARTING 8-NODE CLUSTER BENCHMARK"
echo "   Clients: 4  |  SQL Nodes: 8"
echo "   Time:    ${DURATION}s per level"
echo "=========================================================="

for LEVEL in $CONCURRENCY_LIST; do
    echo ""
    echo "----------------------------------------------------------"
    echo "▶ LEVEL: $LEVEL workers per SQL Node (Cluster Total: $((LEVEL * 8)))"
    echo "----------------------------------------------------------"

    # Function to launch a benchmark instance
    launch_bench() {
        local C_IP=$1
        local S_IP=$2
        local TABS=$3
        local NAME=$4
        local LOG="${OUTPUT_DIR}/vm_${C_IP}_target_${NAME}_level_${LEVEL}.log"
        
        # Run binary in background
        sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no $REMOTE_USER@$C_IP \
            "$REMOTE_BIN \
            -server $S_IP \
            -password '$SQL_PWD' \
            -tables '$TABS' \
            -dataset '$JSONL_FILE' \
            -concurrency $LEVEL \
            -duration $DURATION \
            -topk $TOP_K \
            -top_n $TOP_N" > "$LOG" 2>&1 &
    }

    # --- LAUNCH PHASE ---
    
    # Client 1 -> SQL 1 & 5
    launch_bench $CLIENT1 $SQL1 "1" "SQL1"
    P1=$!
    launch_bench $CLIENT1 $SQL5 "5" "SQL5"
    P2=$!

    # Client 2 -> SQL 2 & 6 AND SQL 4 (Taking load from Client 4)
    launch_bench $CLIENT2 $SQL2 "2" "SQL2"
    P3=$!
    launch_bench $CLIENT2 $SQL6 "6" "SQL6"
    P4=$!
    launch_bench $CLIENT2 $SQL4 "4" "SQL4"
    P7=$!

    # Client 3 -> SQL 3 & 7
    launch_bench $CLIENT3 $SQL3 "3" "SQL3"
    P5=$!
    launch_bench $CLIENT3 $SQL7 "7,9" "SQL7"
    P6=$!

    # Client 4 -> SQL 8 ONLY (Kept Light)
    launch_bench $CLIENT4 $SQL8 "8,10" "SQL8"
    P8=$!

    echo "  ⏳ Running..."
    wait $P1 $P2 $P3 $P4 $P5 $P6 $P7 $P8
    echo "  ✅ Level $LEVEL Complete."

    # --- PARSE PHASE ---
    TOTAL_QPS=0
    SUM_P99=0
    COUNT=0

    for logfile in ${OUTPUT_DIR}/*level_${LEVEL}.log; do
        CLIENT=$(echo $logfile | grep -oE 'vm_[0-9.]+' | sed 's/vm_//')
        TARGET=$(echo $logfile | grep -oE 'target_SQL[0-9]+' | sed 's/target_//')

        QPS=$(grep "Total QPS:" "$logfile" | awk '{print $NF}')
        P99=$(grep -i "P99.*:" "$logfile" | awk '{print $NF}' | sed 's/ms//')
        
        # Defaults
        QPS=${QPS:-0}
        P99=${P99:-0}

        if [[ "$QPS" == "0" ]]; then
            echo "    ⚠️ $CLIENT -> $TARGET: NO DATA"
        else
            echo "    $CLIENT -> $TARGET: $QPS QPS | P99: ${P99}ms"
            COUNT=$((COUNT + 1))
        fi

        TOTAL_QPS=$(python3 -c "print(round($TOTAL_QPS + $QPS, 2))")
        SUM_P99=$(python3 -c "print($SUM_P99 + $P99)")
    done

    if [ "$COUNT" -gt 0 ]; then
        AVG_P99=$(python3 -c "print(round($SUM_P99 / $COUNT, 2))")
    else
        AVG_P99=0
    fi

    echo "  🔥 8-NODE TOTAL QPS: $TOTAL_QPS | Avg P99: ${AVG_P99}ms"
    echo "$LEVEL,$TOTAL_QPS,0,0,$AVG_P99" >> "${OUTPUT_DIR}/summary.csv"
    sleep 5
done

# --- SUMMARY ---
echo ""
echo "=========================================================="
echo "🏆 FINAL SUMMARY - 8 NODE CLUSTER"
echo "=========================================================="
echo ""
printf "%-10s | %-15s | %-10s\n" "Work/Node" "Cluster QPS" "Avg P99"
echo "-------------------------------------------"
if [ -f "${OUTPUT_DIR}/summary.csv" ]; then
    tail -n +2 "${OUTPUT_DIR}/summary.csv" | while IFS=',' read -r lvl qps p50 p95 p99; do
        printf "%-10s | %-15s | %-10s\n" "$lvl" "$qps" "$p99"
    done
fi
echo "-------------------------------------------"
BEST_LINE=$(tail -n +2 "${OUTPUT_DIR}/summary.csv" | sort -t',' -k2 -rn | head -1)
BEST_QPS=$(echo "$BEST_LINE" | cut -d',' -f2)
echo ""
echo "🥇 PEAK QPS: $BEST_QPS"
echo "=========================================================="

