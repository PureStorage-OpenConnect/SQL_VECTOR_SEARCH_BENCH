package main

import (
	"bufio"
	"context"
	"database/sql"
	"flag"
	"fmt"
	"log"
	"math/rand"
	"os"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"unsafe"

	_ "github.com/microsoft/go-mssqldb"
)

// Config
const (
	VectorDim = 768
)

// Flags
var (
	serverStr   = flag.String("server", "10.21.220.8", "SQL Server IP")
	user        = flag.String("user", "sa", "SQL User")
	password    = flag.String("password", "Osmium76&", "SQL Password")
	database    = flag.String("db", "MyDatabase", "Database Name")
	duration    = flag.Int("duration", 60, "Test duration in seconds")
	workers     = flag.Int("concurrency", 50, "Number of concurrent workers")
	
	// UPDATED: Split Output Count vs Scan Depth
	topK        = flag.Int("topk", 10, "Rows to return to client (SELECT TOP)")
	scanDepth   = flag.Int("top_n", 50, "Candidates to scan (DiskANN top_n)")
	
	tablesParam = flag.String("tables", "1", "Comma-separated list of table numbers")
	datasetPath = flag.String("dataset", "/root/golang/vectors_large.jsonl", "Path to the JSONL vector file")
)

var (
	totalQueries uint64
	totalErrors  uint64
)

type WorkerResult struct {
	Latencies []float64
	Errors    map[string]int
}

func main() {
	flag.Parse()

	// 1. Setup Data
	tableNums := strings.Split(*tablesParam, ",")
	var tableNames []string
	for _, num := range tableNums {
		trimmed := strings.TrimSpace(num)
		if trimmed != "" {
			tableNames = append(tableNames, fmt.Sprintf("vectors_copy_%s", trimmed))
		}
	}

	vectors, err := loadVectors(*datasetPath)
	if err != nil {
		log.Fatalf("❌ Error loading dataset: %v", err)
	}

	// PRE-BUILD QUERIES
	// Logic: SELECT TOP(10) ... top_n = 50
	fmt.Println("🔧 Pre-building query templates...")
	queryTemplates := make([]string, len(tableNames))
	for i, tableName := range tableNames {
		queryTemplates[i] = fmt.Sprintf(`DECLARE @v vector(%d) = CAST('%%s' AS vector(%d));
SELECT TOP(%d) t.id 
FROM vector_search(
	table = [benchmark].[%s] as t, 
	column = [emb], 
	similar_to = @v, 
	metric = 'cosine', 
	top_n = %d
) as s`,
			VectorDim, VectorDim, *topK, tableName, *scanDepth)
	}

	fmt.Println("==================================================")
	fmt.Println("   GO BENCHMARK HYPER - Optimized")
	fmt.Println("==================================================")
	fmt.Printf("Target:       %s\n", *serverStr)
	fmt.Printf("Concurrency:  %d\n", *workers)
	fmt.Printf("Recall (top_n): %d\n", *scanDepth)
	fmt.Printf("Output (topk):  %d\n", *topK)

	// 2. Database Connection
	connString := fmt.Sprintf(
		"server=%s;user id=%s;password=%s;database=%s;encrypt=disable;app name=VectorBenchHyper;keepAlive=0;packet size=32767;connection timeout=60;dial timeout=30",
		*serverStr, *user, *password, *database)

	db, err := sql.Open("sqlserver", connString)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// 3. Pool Settings
	db.SetMaxOpenConns(*workers * 3)
	db.SetMaxIdleConns(*workers * 2)
	db.SetConnMaxLifetime(0)
	db.SetConnMaxIdleTime(0)

	// 4. RAMP UP
	fmt.Println("🔌 Ramping up connections...")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var startBarrier sync.WaitGroup
	startBarrier.Add(*workers)

	readyChan := make(chan bool)
	resultsChan := make(chan WorkerResult, *workers)
	var wg sync.WaitGroup

	for i := 0; i < *workers; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()

			myResult := WorkerResult{
				Latencies: make([]float64, 0, 10000),
				Errors:    make(map[string]int),
			}

			r := rand.New(rand.NewSource(time.Now().UnixNano() + int64(id)))

			// Force connection check before starting
			for {
				if err := db.Ping(); err == nil {
					break
				}
				time.Sleep(500 * time.Millisecond)
			}

			startBarrier.Done()
			<-readyChan

			lenVecs := len(vectors)
			lenTabs := len(tableNames)
			
			// OPTIMIZED: Allocation matches requested topK
			idBuf := make([]int64, *topK)

			for {
				select {
				case <-ctx.Done():
					resultsChan <- myResult
					return
				default:
					tableIdx := r.Intn(lenTabs)
					vecStr := vectors[r.Intn(lenVecs)]

					query := fmt.Sprintf(queryTemplates[tableIdx], vecStr)

					t0 := time.Now()

					rows, err := db.Query(query)
					if err != nil {
						atomic.AddUint64(&totalErrors, 1)
						errMsg := err.Error()
						if len(errMsg) > 50 { errMsg = errMsg[:50] + "..." }
						myResult.Errors[errMsg]++
						continue
					}

					// Fast Scan Loop
					rowCount := 0
					for rows.Next() && rowCount < *topK {
						if err := rows.Scan(&idBuf[rowCount]); err != nil {
							break
						}
						rowCount++
					}
					rows.Close()

					duration := time.Since(t0)

					if rowCount > 0 {
						atomic.AddUint64(&totalQueries, 1)
						myResult.Latencies = append(myResult.Latencies, float64(duration.Microseconds())/1000.0)
					} else {
						atomic.AddUint64(&totalErrors, 1)
						myResult.Errors["No rows"]++
					}
				}
			}
		}(i)
	}

	startBarrier.Wait()
	fmt.Println("✅ All connections ready. GO!")

	close(readyChan)
	start := time.Now()

	// Monitor
	monitorTicker := time.NewTicker(5 * time.Second)
	go func() {
		for {
			<-monitorTicker.C
			if time.Since(start).Seconds() >= float64(*duration) {
				cancel()
				return
			}
			curr := atomic.LoadUint64(&totalQueries)
			elap := time.Since(start).Seconds()
			fmt.Printf("   [%3.0fs] QPS: %.0f\n", elap, float64(curr)/elap)
		}
	}()

	wg.Wait()
	close(resultsChan)
	finalTime := time.Since(start).Seconds()

	// 5. Stats
	fmt.Println("\n📊 CALCULATING STATISTICS...")
	var allLatencies []float64
	combinedErrors := make(map[string]int)

	for res := range resultsChan {
		allLatencies = append(allLatencies, res.Latencies...)
		for msg, count := range res.Errors {
			combinedErrors[msg] += count
		}
	}

	var p50, p99 float64
	if len(allLatencies) > 0 {
		sort.Float64s(allLatencies)
		p50 = allLatencies[int(float64(len(allLatencies))*0.50)]
		p99 = allLatencies[int(float64(len(allLatencies))*0.99)]
	}

	fmt.Println("==================================================")
	fmt.Printf("Concurrency:   %d\n", *workers)
	fmt.Printf("Total QPS:     %.2f\n", float64(len(allLatencies))/finalTime)
	fmt.Printf("P50 Latency:   %.2f ms\n", p50)
	fmt.Printf("P99 Latency:   %.2f ms\n", p99)
	fmt.Printf("Errors:        %d\n", totalErrors)
	fmt.Println("==================================================")
}

func loadVectors(path string) ([]string, error) {
	file, err := os.Open(path)
	if err != nil { return nil, err }
	defer file.Close()
	var vecs []string
	scanner := bufio.NewScanner(file)
	buf := make([]byte, 64*1024)
	scanner.Buffer(buf, 64*1024)
	for scanner.Scan() {
		t := strings.TrimSpace(scanner.Text())
		if t != "" { vecs = append(vecs, t) }
	}
	return vecs, scanner.Err()
}
var _ = unsafe.Sizeof(0)
