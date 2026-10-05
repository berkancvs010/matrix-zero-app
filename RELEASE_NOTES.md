# ZeroLog 1.0.10+34

## Retro hardening
- Retro arcade reduced to 9 distinct offline games; duplicate/generic entries removed.
- Virtual gamepad hit targets now use explicit semantics and only render A/B actions when an action is actually bound.
- Tetris virtual gamepad Down now updates state correctly; A rotates pieces; B restarts the board; rotation uses collision validation.
- 2048 now detects win and no-move game-over states and prevents input after terminal state.
- Fixed the previous Build 32 compile defects and kept Retro isolated from call, FCM, WebRTC, privacy-lock and file-transfer code.
