#!/bin/bash
# ==============================================================================
# CLUSTER BENCHMARK - GO EDITION (search_engine_v1)
# Orchestrates 4 VMs running the pre-compiled Go binary
# ==============================================================================

# --- CONFIGURATION ---
REMOTE_USER="root"
REMOTE_PASS="yourpassword"

# Location of the binary on client VMs /host machines
REMOTE_BIN="/root/golang/search_engine_v1"


# Dataset location on REMOTE VMs
JSONL_FILE="/root/golang/vectors_large.jsonl"


# SQL Connection Details
SQL_IP="10.2XX.XX.XX"
SQL_PWD="yourpassword"

# Bench Settings
DURATION=30
# Concurrency steps: 10 to 100 in steps of 5
CONCURRENCY_LIST="10 20 30 40 50 60 70 80 90 100"

# Search Parameters
TOP_K=10      # Rows to return (SELECT TOP X)
TOP_N=50      # Candidates to scan (top_n = X) - Tuned for speed

# --- VM MAPPING ---
# VM1 & VM2 -> Node 1 Tables
VM1_IP="10.21.220.XX"; VM1_TABLES="1,4"
VM2_IP="10.21.220.XX"; VM2_TABLES="2,5,10"

# VM3 & VM4 -> Node 2 Tables
VM3_IP="10.21.220.XX"; VM3_TABLES="7,8,3"
VM4_IP="10.21.220.XX"; VM4_TABLES="9,6"

ALL_VMS="$VM1_IP $VM2_IP $VM3_IP $VM4_IP"

# --- SETUP OUTPUT ---
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="./go_cluster_results_${TIMESTAMP}"
mkdir -p "$OUTPUT_DIR"
echo "Concurrency,TotalQPS" > "${OUTPUT_DIR}/summary.csv"

# --- CLEANUP TRAP ---
cleanup() {
    echo ""
    echo "🧹 Cleaning up remote processes..."
    for ip in $ALL_VMS; do
        sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no $REMOTE_USER@$ip \
            "pkill -f search_engine_v1" 2>/dev/null &
    done
    wait
    exit
}
trap cleanup EXIT INT TERM

echo "=========================================================="
echo "🚀 STARTING GO CLUSTER BENCHMARK"
echo "   Binary: $REMOTE_BIN"
echo "   Duration: ${DURATION}s"
echo "=========================================================="

# --- RUN BENCHMARK LOOP ---
for LEVEL in $CONCURRENCY_LIST; do
    echo ""
    echo "----------------------------------------------------------"
    echo "▶ LEVEL: $LEVEL workers per VM (Cluster Total: $((LEVEL * 4)))"
    echo "----------------------------------------------------------"

    # Function to trigger remote run in background
    run_vm() {
        local IP=$1
        local TABLES=$2
        local LOG="${OUTPUT_DIR}/vm_${IP}_level_${LEVEL}.log"
        
        # Run the binary directly
        sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no $REMOTE_USER@$IP \
            "$REMOTE_BIN \
            -server $SQL_IP \
            -password '$SQL_PWD' \
            -tables '$TABLES' \
            -dataset '$JSONL_FILE' \
            -concurrency $LEVEL \
            -duration $DURATION \
            -topk $TOP_K \
            -top_n $TOP_N" > "$LOG" 2>&1 &
    }

    # Launch all 4 VMs simultaneously
    run_vm $VM1_IP "$VM1_TABLES"
    PID1=$!
    run_vm $VM2_IP "$VM2_TABLES"
    PID2=$!
    run_vm $VM3_IP "$VM3_TABLES"
    PID3=$!
    run_vm $VM4_IP "$VM4_TABLES"
    PID4=$!

    echo "  ⏳ Running for ${DURATION}s..."
    wait $PID1 $PID2 $PID3 $PID4
    echo "  ✅ Level $LEVEL Complete."

    # --- PARSE RESULTS ---
    TOTAL_QPS=0
    for ip in $ALL_VMS; do
        LOG="${OUTPUT_DIR}/vm_${ip}_level_${LEVEL}.log"
        
        # FIX: Grep for 'Total QPS:' and take the LAST field ($NF) to handle spaces
        QPS=$(grep "Total QPS:" "$LOG" | awk '{print $NF}')
        
        # Check if QPS is empty or not a number
        if [[ -z "$QPS" ]]; then 
            QPS=0
            echo "    ⚠️ VM $ip FAILED. Debug info:"
            echo "       Log: $LOG"
            echo "       Last 3 lines:"
            tail -n 3 "$LOG" | sed 's/^/         /'
        else
            echo "    VM $ip: $QPS QPS"
        fi
        
        # Python math for float addition
        TOTAL_QPS=$(python3 -c "print(round($TOTAL_QPS + $QPS, 2))")
    done

    echo "  🔥 CLUSTER TOTAL QPS: $TOTAL_QPS"
    echo "$LEVEL,$TOTAL_QPS" >> "${OUTPUT_DIR}/summary.csv"
    
    # Short cooldown
    sleep 5
done

echo ""
echo "=========================================================="
echo "🏆 BENCHMARK COMPLETE"
echo "   Results saved to: $OUTPUT_DIR"
echo "=========================================================="
