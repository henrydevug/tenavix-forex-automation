# TENAVIX FOREX AUTOMATION PLATFORM

**Version:** 1.0  
**Status:** In Development  
**Project Type:** Subscription-based MT5 Forex Automation Platform

Tenavix is a subscription-based forex trading automation platform that connects MetaTrader 5 accounts to a risk-controlled Expert Advisor (EA).

The platform combines MQL5, Dart, Serverpod and PostgreSQL to provide automated trade execution, centralized subscription management, account isolation and risk controls.

Its engineering priorities are **safety**, **auditability**, **reliability** and **disciplined execution** rather than profit claims.

> **Important:** Tenavix does not guarantee profits or risk-free trading. Demo and simulation testing are the default development priorities. Live trading must remain disabled until the necessary validation and explicit release authorization are completed.

---

## 1. Project Objectives

- Automate trade entry and exit based on configured strategies.
- Enforce stop-loss, take-profit and trailing stop-loss controls.
- Calculate position sizes using configurable risk limits.
- Protect accounts through maximum daily loss controls.
- Provide manual override and emergency-stop functionality.
- Manage subscriptions, licenses and connected MT5 accounts.
- Maintain auditable records of important system operations.

---

## 2. Technology Stack

| Layer            | Technology                 |
| ---------------- | -------------------------- |
| Trading platform | MetaTrader 5               |
| Expert Advisor   | MQL5                       |
| Backend          | Dart and Serverpod         |
| Database         | PostgreSQL                 |
| Web frontend     | HTML5, CSS3 and JavaScript |
| Infrastructure   | Docker and Docker Compose  |
| Version control  | Git and GitHub             |
| CI/CD            | GitHub Actions             |

---

## 3. Repository Structure

```
tenavix/
├── docs/                    # Engineering documentation
├── mt5/                     # MQL5 Expert Advisor
│   ├── Experts/
│   └── Include/Tenavix/
├── tenavix_server/          # Dart / Serverpod backend
├── tenavix_web/             # Responsive web frontend
├── infrastructure/          # Deployment configurations
├── scripts/                 # Utility scripts
├── tests/                   # Automated and manual tests
└── .github/workflows/       # CI/CD pipelines
```

---

## 4. Engineering Documentation

| Document                            | Location                                       |
| ----------------------------------- | ---------------------------------------------- |
| Project Overview                    | [docs/01_Project_Overview.md](docs/01_Project_Overview.md) |
| Software Requirements Specification | [docs/02_Software_Requirements_Specification.md](docs/02_Software_Requirements_Specification.md) |
| System Architecture                 | [docs/03_System_Architecture.md](docs/03_System_Architecture.md) |
| Database Design                     | [docs/05_Database_Design.md](docs/05_Database_Design.md) |
| Risk Assessment Matrix              | [docs/08_Risk_Assessment_Matrix.md](docs/08_Risk_Assessment_Matrix.md) |
| Requirements Traceability Matrix    | [docs/09_Requirements_Traceability_Matrix.md](docs/09_Requirements_Traceability_Matrix.md) |

Additional documentation covers UML models, architecture decisions, CRUD matrices, API design, security, testing and deployment.

---

## 5. Development Principles

Tenavix follows disciplined software engineering practices:

- SOLID principles and object-oriented design.
- Separation of concerns and modular architecture.
- Secure authentication and role-based access control.
- Database constraints and transaction integrity.
- Account isolation and subscription validation.
- Fail-safe defaults and defence in depth.
- Auditability and traceability of requirements.
- Automated testing and continuous integration.

---

## 6. Development Progress

The project is being developed incrementally using a structured Software Development Life Cycle (SDLC).

Current development foundations include:

- **Sprint 1:** Requirements, architecture, database design, UML and engineering matrices.
- **Sprint 2:** Backend foundation, authentication, RBAC, account isolation, licensing and security tests.
- **Sprint 3:** MQL5 Expert Advisor foundation, modular risk management, strategy, execution and license client.

These milestones represent implementation progress, **not** a declaration that the entire platform is production-ready.

---

## 7. Getting Started

Clone the repository:

```bash
git clone https://github.com/henrydevug/tenavix-forex-automation.git
cd tenavix-forex-automation
```

Inspect the documentation:

```bash
ls docs/
```

Review the relevant backend, frontend and MT5 project instructions before running individual components.

---

## 8. Security and Trading Disclaimer

- Broker trading passwords must not be stored by the backend.
- Authentication credentials and license data must be protected.
- Trading operations must enforce configured risk limits.
- Live trading requires explicit authorization and appropriate testing.
- Trading involves substantial risk of financial loss.

---

## 9. License

Proprietary — All rights reserved.

Unauthorized copying, redistribution or commercial use is prohibited.

**Tenavix** — Ingenuity and Lucidity in Financial Technology.
