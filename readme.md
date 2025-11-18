# rPPG iOS App

Remote photoplethysmography (rPPG) iOS app for contactless heart-rate / HRV estimation from the smartphone camera. This is mine (Jonathan Kierce) and Aydan Kumar's Final Year Project.

## Repository Structure

    .
    ├── rppg-app/   # iOS app source code
    └── docs/       # Submitted report(s), paper, presentation slides, etc.

---

## rppg-app/ – iOS Application

This folder contains the Xcode project for the iOS app.

---

## docs/ – Project Documentation

This folder holds the artefacts submitted for assessment:

- Final written report / paper (PDF)
- Presentation slides

---

## Getting Started

### Prerequisites

- macOS with a recent version of Xcode installed
- An iPhone (physical device recommended; camera access in the Simulator is limited)
- Apple Developer account if you want to deploy to a physical device

### Build and Run

1.  Clone the repository:

        git clone <REPO_URL>
        cd <REPO_FOLDER>

2.  Open the iOS project in Xcode:

         open rppg-app/*.xcodeproj

    or open the `.xcworkspace` if one exists.

3.  In Xcode:

    - Select the app target.
    - Choose your development team for code signing.
    - Select your device (or a simulator) from the scheme menu.
    - Press **Run**.

4.  On first launch, grant camera permissions.

---
