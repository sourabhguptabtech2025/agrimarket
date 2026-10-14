@echo off
title AgriMarket Web Application Launcher
cd /d "%~dp0"
echo =====================================================================
echo Starting AgriMarket Web Application (Streamlit + MySQL)
echo URL: http://localhost:8501
echo =====================================================================
python -m streamlit run app.py
pause
