package main

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"flag"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/natefinch/lumberjack"
	slogmulti "github.com/samber/slog-multi"
)

// Default config constants (can be overridden via command-line flags)
// - LogPath: Path to the log file where service logs are written.
// - Port: Port on which the HTTP service will listen.
// - SocketPath: Path to the Unix socket file for the service.
// - VerifierRoot: Root directory for the GPU verifier, containing the Python script.
// - SuccessStr: Message indicating successful attestation in command output.
const (
	defaultLogPath       = "/usr/local/bin/local_gpu_verifier_http_service/attestation_service.log"
	defaultPort          = "8123"
	defaultSocketPath    = "/var/run/gpu-attestation/gpu-attestation.sock"
	defaultVerifierRoot  = "/usr/local/lib/local_gpu_verifier"
	defaultSuccessString = "GPU Attestation is Successful"
	defaultNonceSize     = 32
)

// Config holds runtime configuration for the GPU Attestation HTTP Service
type Config struct {
	LogPath      string
	Port         string
	SocketPath   string
	VerifierRoot string
	SuccessStr   string
}

var (
	// global logger
	logger *slog.Logger

	// enableDebugLogging is a build-time flag defaults to false
	// To build with debug logging enabled, pass:
	// -ldflags="-X main.enableDebugLogging=true"
	enableDebugLogging string = "false"

	// Mutex to protect access to the GPU attestation process
	// This ensures only one attestation process runs at a time
	attestationMutex sync.Mutex
)

// createServer configures and returns a server with common settings
// This can be used for both HTTP and Unix socket servers
func createServer(mux *http.ServeMux) *http.Server {
	return &http.Server{
		Handler:      mux,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
	}
}

// startHTTPServer starts the HTTP server on the specified port
func startHTTPServer(wg *sync.WaitGroup, port string, mux *http.ServeMux) {
	defer wg.Done()

	srv := createServer(mux)
	srv.Addr = ":" + port

	logger.Info("Starting HTTP server", "port", port)
	if err := srv.ListenAndServe(); err != http.ErrServerClosed {
		logger.Error("HTTP server failed", "err", err)
	}
}

// prepareSocketListener creates and prepares a Unix socket listener
func prepareSocketListener(socketPath string) (net.Listener, error) {
	// Remove socket if it already exists
	if _, err := os.Stat(socketPath); err == nil {
		if err := os.Remove(socketPath); err != nil {
			logger.Error("Failed to remove existing socket file", "err", err)
			return nil, err
		}
	}

	// Create the directory for the socket file if it doesn't exist
	socketDir := filepath.Dir(socketPath)
	if err := os.MkdirAll(socketDir, 0755); err != nil {
		logger.Error("Failed to create socket directory", "err", err)
		return nil, err
	}

	// Create listener
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		logger.Error("Failed to create Unix socket", "err", err)
		return nil, err
	}

	// Set permissive file permissions for the socket
	if err := os.Chmod(socketPath, 0666); err != nil {
		logger.Error("Failed to set socket permissions 0666", "err", err)
		// Continue even if chmod fails
		// In this case the user must have permissions to access the socket
	}

	return listener, nil
}

// startSocketServer starts the Unix socket server
func startSocketServer(wg *sync.WaitGroup, socketPath string, mux *http.ServeMux) {
	defer wg.Done()

	listener, err := prepareSocketListener(socketPath)
	if err != nil {
		return
	}
	defer listener.Close()

	srv := createServer(mux)

	logger.Info("Starting Unix socket server", "socket", socketPath)
	if err := srv.Serve(listener); err != http.ErrServerClosed {
		logger.Error("Socket server failed", "err", err)
	}
}

func main() {
	// Initialize logger to output to stderr while we load configuration
	initLogger("")

	// Parse the command-line flags for service configuration
	logPath := flag.String("logpath", defaultLogPath, "Path to the log file where service logs are written.")
	port := flag.String("port", defaultPort, "Port on which the HTTP service will listen.")
	socketPath := flag.String("socket", defaultSocketPath, "Path to the Unix socket file.")
	verifierRoot := flag.String("verifierroot", defaultVerifierRoot, "Root directory for the GPU verifier, containing the Python script.")
	successStr := flag.String("successstr", defaultSuccessString, "Message indicating successful attestation in command output.")
	flag.Parse()

	logger.Info("Loading service configuration...",
		"logPath", *logPath,
		"port", *port,
		"socketPath", *socketPath,
		"verifierRoot", *verifierRoot,
		"successStr", *successStr,
	)

	config := Config{
		LogPath:      *logPath,
		Port:         *port,
		SocketPath:   *socketPath,
		VerifierRoot: *verifierRoot,
		SuccessStr:   *successStr,
	}

	// Re-initialize the logger with file + console handlers
	initLogger(config.LogPath)

	// Log service startup details
	logger.Info("Starting GPU Attestation Service")
	logger.Info("Log file", "path", config.LogPath)
	logger.Info("GPU attestation Verifier root directory", "path", config.VerifierRoot)

	// Setup the HTTP handler
	mux := http.NewServeMux()
	mux.HandleFunc("/gpu_attest", func(w http.ResponseWriter, r *http.Request) {
		handleGpuAttest(w, r, config)
	})

	// Start servers in goroutines
	var wg sync.WaitGroup

	// Start HTTP server
	wg.Add(1)
	go startHTTPServer(&wg, config.Port, mux)

	// Start Unix socket server
	wg.Add(1)
	go startSocketServer(&wg, config.SocketPath, mux)

	// Wait for servers to exit
	wg.Wait()
}

// (Re)initializes the global logger
// It uses the global enableDebugLogging flag to set the log level.
// If logPath is non-empty, it logs to both the specified file and stderr.
// Otherwise, it logs only to stderr.
func initLogger(logPath string) {
	var level slog.Level
	if enableDebugLogging == "true" {
		level = slog.LevelDebug
	} else {
		level = slog.LevelInfo
	}

	// Create a console handler that writes to stderr
	consoleHandler := slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: level})
	logger = slog.New(consoleHandler)

	// If logPath is not empty, use lumberjack to rotate logs
	if logPath != "" {
		logWriter := &lumberjack.Logger{
			Filename: logPath,
			MaxSize:  50,   // megabytes
			MaxAge:   365,  // days to keep
			Compress: true, // compress the old logs
		}

		fileHandler := slog.NewTextHandler(logWriter, &slog.HandlerOptions{Level: level})
		multiHandler := slogmulti.Fanout(fileHandler, consoleHandler)
		logger = slog.New(multiHandler)
	}
}

// handleGpuAttest runs the GPU attestation command, captures output, and returns a response
func handleGpuAttest(w http.ResponseWriter, r *http.Request, config Config) {
	start := time.Now()

	// Log incoming request details
	logger.Debug("Incoming GPU attestation request",
		"method", r.Method,
		"remote_addr", r.RemoteAddr,
		"headers", r.Header,
	)

	// Parse request ID from request header or generate a new one
	var requestIdFields = []string{"x-request-id", "x-ms-request-id", "request-id", "requestid"}
	var reqId string
	for _, key := range requestIdFields {
		if val := r.Header.Get(key); val != "" {
			reqId = val
			logger.Info("Found request ID in header", "request_id", reqId)
			break
		}
	}
	if reqId == "" {
		reqId = uuid.NewString()
		logger.Info("Assign new request ID", "request_id", reqId)
	}

	// Create a request-scoped logger that includes request_id in every log
	reqLogger := logger.With("request_id", reqId)

	// Also set x-ms-request-id in the response
	w.Header().Set("x-ms-request-id", reqId)

	// Optional nonce in POST request body or GET request query param
	var nonce string
	switch r.Method {
	case http.MethodGet:
		reqLogger.Info("GET request query", "params", r.URL.Query())
		nonce = r.URL.Query().Get("nonce")

	case http.MethodPost:
		// Log the request body
		bodyBytes, err := io.ReadAll(r.Body)
		if err != nil {
			reqLogger.Error("Failed to read request body", "error", err)
			http.Error(w, "Failed to read request body", http.StatusBadRequest)
			return
		}
		r.Body.Close()
		r.Body = io.NopCloser(bytes.NewBuffer(bodyBytes))
		reqLogger.Info("POST request body", "body", string(bodyBytes))

		// Parse request body as JSON
		type gpuAttestRequest struct {
			Nonce string `json:"nonce"`
		}
		var attReq gpuAttestRequest
		if err := json.Unmarshal(bodyBytes, &attReq); err == nil {
			nonce = attReq.Nonce // might be empty if not present
		}

	default:
		reqLogger.Warn("Method not allowed", "method", r.Method)
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	// Log the nonce if present
	if nonce == "" {
		reqLogger.Info("No nonce provided in request")
	} else {
		reqLogger.Info("Nonce found in request", "nonce", nonce)
		// Check if the nonce is a valid hex string representing 32 bytes
		if !isValidHex(nonce, defaultNonceSize) {
			reqLogger.Error("Invalid nonce provided; must be a hex string representing 32 bytes", "nonce", nonce)
			http.Error(w, "Invalid args: nonce must be a 32-byte hex string", http.StatusBadRequest)
			return
		}
	}

	// Execute the GPU attestation command with no concurrent runs
	combinedOutput, runErr := executeAttestationCommand(reqLogger, config.VerifierRoot, nonce)

	if runErr != nil {
		reqLogger.Error("Error executing cc_admin", "error", runErr)
		respondJSON(w, http.StatusInternalServerError, combinedOutput, nil)
		reqLogger.Error("Completed /gpu_attest with HTTP 500", "duration", time.Since(start))
		return
	}

	// Determine success based on the output message
	isSuccess := strings.Contains(combinedOutput, config.SuccessStr)

	// Extract attestation token if available
	attToken := parseToken(combinedOutput)

	// Assign HTTP status code, 200 if attestation succeeded, 400 if failed
	statusCode := http.StatusOK
	if !isSuccess {
		statusCode = http.StatusBadRequest
	}

	// Respond with JSON output
	respondJSON(w, statusCode, combinedOutput, attToken)
	reqLogger.Info("Completed /gpu_attest",
		"duration", time.Since(start),
		"status_code", statusCode,
	)
}

// Execute the GPU attestation command
func executeAttestationCommand(reqLogger *slog.Logger, verifierRoot string, nonce string) (string, error) {
	pythonPath := filepath.Join(verifierRoot, "prodtest", "bin", "python3")
	cmd := exec.Command("sudo", pythonPath, "-m", "verifier.cc_admin")

	// Add nonce if provided (nonce is already validated before reaching here)
	if nonce != "" {
		cmd.Args = append(cmd.Args, "--nonce", nonce)
	}

	var outBuf, errBuf bytes.Buffer
	cmd.Stdout = &outBuf
	cmd.Stderr = &errBuf

	attestationMutex.Lock()
	runErr := cmd.Run()
	attestationMutex.Unlock()

	combinedOutput := outBuf.String() + errBuf.String()
	reqLogger.Info("GPU Attestation Command output", "output", combinedOutput)

	return combinedOutput, runErr
}

// isValidHex checks if s is a valid hex string representing exactly numBytes bytes
func isValidHex(s string, numBytes int) bool {
	// Check string length should be twice the number of bytes
	if len(s) != numBytes*2 {
		return false
	}
	// Try decoding the hex string
	decoded, err := hex.DecodeString(s)
	if err != nil {
		return false
	}
	// Ensure the decoded byte slice has the expected length
	return len(decoded) == numBytes
}

// parseToken extracts the Entity Attestation Token from the output
func parseToken(output string) interface{} {
	lines := strings.Split(output, "\n")
	for i, line := range lines {
		if strings.Contains(line, "Entity Attestation Token:") {
			// Attempt to parse the following lines as JSON
			jsonCandidate := strings.Join(lines[i+1:], "\n")
			jsonCandidate = strings.TrimSpace(jsonCandidate)

			var token interface{}
			if err := json.Unmarshal([]byte(jsonCandidate), &token); err == nil {
				return token
			}
			break
		}
	}
	return nil
}

// respondJSON sends a JSON response to the client
func respondJSON(w http.ResponseWriter, statusCode int, attestationOutput string, token interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)

	resp := map[string]interface{}{
		"attestation_output":       attestationOutput,
		"entity_attestation_token": token,
	}
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	if err := enc.Encode(resp); err != nil {
		logger.Error("Error encoding JSON response", "error", err)
	}
}
