<<<<<<< HEAD
# TENAVIX FOREX AUTOMATION PLATFORM

**Version:** 1.0 (In Development)  
**Status:** Sprint 1 — Requirements, Architecture & Design

Tenavix is a subscription-based forex trading automation platform that connects MetaTrader 5 accounts to a risk-controlled Expert Advisor. The platform prioritizes safety, auditability and disciplined execution over profit claims.

> **Important:** This software does not guarantee profits or risk-free trading. Default operating mode is DEMO / SIMULATION. Live trading remains disabled until explicit release authorization after validation.

## Repository Structure

```
tenavix/
├── docs/                    # Engineering documentation (SRS, Architecture, Matrices, ADRs...)
├── mt5/                     # MQL5 Expert Advisor and includes
│   ├── Experts/
│   └── Include/Tenavix/
├── tenavix_server/          # Dart / Serverpod backend
├── tenavix_web/             # Responsive web frontend (HTML/CSS/JS)
├── infrastructure/          # Docker, reverse-proxy, deployment configs
├── scripts/                 # Utility and operational scripts
├── tests/                   # Unit, integration, security, MT5 tests
└── .github/workflows/       # CI/CD pipelines
```

## Documentation Index

| # | Document |
|---|----------|
| 01 | [Project Overview](docs/01_Project_Overview.md) |
| 02 | [Software Requirements Specification](docs/02_Software_Requirements_Specification.md) |
| 03 | [System Architecture](docs/03_System_Architecture.md) |
| 05 | [Database Design](docs/05_Database_Design.md) |
| 08 | [Risk Assessment Matrix](docs/08_Risk_Assessment_Matrix.md) |
| 09 | [Requirements Traceability Matrix](docs/09_Requirements_Traceability_Matrix.md) |

Additional documents (UML, API, Security Threat Model, Test Strategy, Deployment Guide, etc.) are produced as the project advances through the defined sprints.

## Technology Stack

- **Trading:** MetaTrader 5 / MQL5
- **Backend:** Dart + Serverpod
- **Database:** PostgreSQL
- **Frontend:** HTML5, CSS3, JavaScript (responsive)
- **Infrastructure:** Docker, Docker Compose, GitHub Actions

## Development Principles

- SOLID, Clean Architecture, Separation of Concerns
- Local-first safety controls (emergency stop, risk state)
- Backend never holds broker trading passwords
- Fail-safe defaults and defence in depth
- Every Must requirement traced to design and tests

## Getting Started (Current State)

Sprint 1 is focused on requirements analysis, architecture, database design and engineering matrices. Implementation begins in Sprint 2.

```bash
# Clone (once remote is configured)
git clone <repository-url>
cd tenavix

# Documentation is the current primary deliverable
ls docs/
```

## License & Disclaimer

Proprietary — All rights reserved.  
Trading involves substantial risk of loss. Past performance is not indicative of future results. Use only with capital you can afford to lose, preferably on demo accounts first.

---

*Maintained according to the Master Software Engineering Prompt for TENAVIX v1.0*
=======
# tenavix-forex-automation
A subscription-based MT5 forex automation platform built with MQL5, Dart, Serverpod and PostgreSQL.
>>>>>>> origin/main
