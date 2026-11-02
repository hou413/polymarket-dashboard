#!/bin/bash
# Sync Smart v2 data to GitHub Pages as static JSON
# Runs every 5 minutes via LaunchAgent

set -e

DATA_SOURCE="/Users/openbren/.openclaw/workspace-smart/polymarket-smart-money/data/today-trades.json"
STATS_SOURCE="/Users/openbren/.openclaw/workspace-smart/polymarket-smart-money/data/stats.json"
REPO_DIR="/tmp/polymarket-dashboard"
OUTPUT_FILE="$REPO_DIR/data.json"

# Check if source data exists
if [ ! -f "$DATA_SOURCE" ]; then
  echo "[$(date)] No data file found, skipping sync"
  exit 0
fi

# Generate static JSON using dashboard-api logic
cd /Users/openbren/.openclaw/workspace-smart/polymarket-smart-money
node -e "
const { readFileSync, writeFileSync } = require('fs');
const { join } = require('path');

// Inline the processData logic from dashboard-api.js
const DATA_FILE = '$DATA_SOURCE';
const STATS_FILE = '$STATS_SOURCE';
const MARKET_ANALYSIS_FILE = join(__dirname, 'data', 'market_analysis.json');

const CATEGORY_PATTERNS = {
  sports: [/nba|nfl|nhl|mlb|mls|ufc|cfl/i, /spread:|o\/u|total|score/i, /vs\.|vs /i, /soccer|football|epl|la liga|bundesliga|serie a|ligue 1|champions league|uefa/i, /fc |cf |sc |united|city|real|barcelona|bayern|juventus|inter|milan/i],
  politics: [/ceasefire|iran|trump|biden|harris|republican|democrat|election|house|senate|congress/i, /president|prime minister/i],
  weather: [/temperature|weather|climate|rain|snow|hurricane|earthquake/i],
  tech: [/google|gemini|openai|gpt|claude|anthropic|meta|apple|microsoft|amazon|tesla|spacex/i, /ai |arena|leaderboard|model|llm/i, /wti|crude oil|oil price|gold|silver/i, /interest rate|fed |fomc|ecb |inflation/i],
};

const EXCLUDE_PATTERNS = [/up or down - .*(1h|15m|5m|30m|10m|1m|et)$/i, /bitcoin up or down/i, /ethereum up or down/i];

function categorize(trade) {
  const title = (trade.question || trade.market || trade.raw?.title || '').toLowerCase();
  const slug = (trade.slug || trade.raw?.slug || '').toLowerCase();
  const text = title + ' ' + slug;
  for (const pat of EXCLUDE_PATTERNS) if (pat.test(text)) return 'excluded';
  for (const [cat, patterns] of Object.entries(CATEGORY_PATTERNS)) {
    for (const pat of patterns) if (pat.test(text)) return cat;
  }
  return 'other';
}

function buildMarketUrl(slug, title) {
  if (slug) return 'https://polymarket.com/event/' + slug + '?utm_source=smart_v2_dashboard';
  return null;
}

try {
  const trades = JSON.parse(readFileSync(DATA_FILE, 'utf-8'));
  const stats = JSON.parse(readFileSync(STATS_FILE, 'utf-8'));
  
  const now = Date.now();
  const sevenDaysAgo = now - 7 * 24 * 60 * 60 * 1000;
  const recentTrades = trades.filter(t => (t.timestamp || 0) >= sevenDaysAgo);
  
  const categorized = { sports: [], politics: [], weather: [], tech: [], other: [] };
  
  for (const trade of recentTrades) {
    const cat = trade.category || categorize(trade);
    if (cat === 'excluded') continue;
    const enriched = { ...trade, category: cat, marketUrl: buildMarketUrl(trade.slug, trade.question || trade.market) };
    if (categorized[cat]) categorized[cat].push(enriched);
    else categorized.other.push(enriched);
  }
  
  const summaries = {};
  for (const [cat, catTrades] of Object.entries(categorized)) {
    const buys = catTrades.filter(t => t.side === 'BUY');
    const sells = catTrades.filter(t => t.side === 'SELL');
    summaries[cat] = {
      count: catTrades.length,
      buyCount: buys.length,
      sellCount: sells.length,
      buyVolume: buys.reduce((s, t) => s + t.value, 0),
      sellVolume: sells.reduce((s, t) => s + t.value, 0),
      totalVolume: buys.reduce((s, t) => s + t.value, 0) + sells.reduce((s, t) => s + t.value, 0),
      recentTrades: catTrades.sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0)).slice(0, 20).map(t => ({
        time: new Date(t.timestamp).toISOString(),
        market: t.question || t.market,
        slug: t.slug,
        url: t.marketUrl,
        side: t.side,
        value: t.value,
        direction: t.direction,
        price: t.price,
        outcome: t.outcome,
      })),
    };
  }
  
  const allTrades = Object.values(categorized).flat()
    .sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0))
    .map(t => ({
      time: new Date(t.timestamp).toISOString(),
      market: t.question || t.market,
      slug: t.slug,
      url: t.marketUrl,
      side: t.side,
      value: t.value,
      direction: t.direction,
      price: t.price,
      category: t.category,
    }));
  
  const output = {
    stats,
    categories: summaries,
    recent: allTrades,
    winRates: {},
    generatedAt: new Date().toISOString(),
  };
  
  writeFileSync('$OUTPUT_FILE', JSON.stringify(output, null, 2));
  console.log('Generated data.json with', allTrades.length, 'trades');
} catch (e) {
  console.error('Error:', e.message);
  process.exit(1);
}
"

# Commit and push to GitHub
cd "$REPO_DIR"
git add data.json
if git diff --cached --quiet; then
  echo "[$(date)] No changes to sync"
else
  git commit -m "Update data: $(date '+%Y-%m-%d %H:%M:%S')"
  git push origin main
  echo "[$(date)] Synced to GitHub Pages"
fi
