# Auto-merge configuration

# Auto-merge rules for different branch patterns

## Documentation branches (docs/**)
- Pattern: `docs/**`
- Auto-merge: YES (after CI passes)
- Require review: NO
- Strategy: squash

## Feature branches (feat/**)
- Pattern: `feat/**`
- Auto-merge: NO
- Require review: YES (1 approval)
- Strategy: merge

## Fix branches (fix/**)
- Pattern: `fix/**`
- Auto-merge: CONDITIONAL (if tests pass + no breaking changes)
- Require review: YES (1 approval)
- Strategy: merge

## Configuration

To enable Telegram notifications:
1. Create a Telegram bot via @BotFather
2. Get your chat ID via @userinfobot
3. Add secrets to GitHub:
   - `TELEGRAM_BOT_TOKEN`: your bot token
   - `TELEGRAM_CHAT_ID`: your chat ID

## GitHub Actions secrets needed:
- `TELEGRAM_BOT_TOKEN` (optional)
- `TELEGRAM_CHAT_ID` (optional)
