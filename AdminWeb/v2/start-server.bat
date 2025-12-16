@echo off
echo ========================================
echo   SMART AC ADMIN - Starting Server
echo ========================================
echo.
echo Starting Python HTTP Server on port 8000...
echo.
echo Open your browser and go to:
echo http://localhost:8000
echo.
echo Press Ctrl+C to stop the server
echo ========================================
echo.

python -m http.server 8000

pause
