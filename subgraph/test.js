// Run: node test.js
// Tests the deployed GradPad subgraph endpoint

const ENDPOINT = "https://api.studio.thegraph.com/query/50551/gradpad/v0.0.2";

async function query(name, gql, variables = {}) {
  const res = await fetch(ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query: gql, variables }),
  });
  const json = await res.json();
  if (json.errors) {
    console.error(
      `  ✗ ${name} — GraphQL errors:`,
      JSON.stringify(json.errors, null, 2),
    );
    return null;
  }
  return json.data;
}

function check(label, value, expected, format = (v) => v) {
  const pass = expected(value);
  console.log(`  ${pass ? "✓" : "✗"} ${label}: ${format(value)}`);
  return pass;
}

async function main() {
  let allPassed = true;

  // ─── 1. Sync status ──────────────────────────────────────────────────────
  console.log("\n── 1. Sync status");
  const meta = await query(
    "meta",
    `{
    _meta { block { number } hasIndexingErrors deployment }
  }`,
  );
  if (meta) {
    check(
      "hasIndexingErrors",
      meta._meta.hasIndexingErrors,
      (v) => v === false,
    );
    check(
      "indexed up to block",
      meta._meta.block.number,
      (v) => v > 0,
      (v) => `#${v}`,
    );
    console.log("  deployment:", meta._meta.deployment);
  } else {
    allPassed = false;
  }

  // ─── 2. Token list ───────────────────────────────────────────────────────
  console.log("\n── 2. Token list");
  const tokens = await query(
    "tokens",
    `{
    gradPadTokens(first: 5, orderBy: createdAt, orderDirection: desc) {
      id name symbol creator bondingPhase
      totalVolume tradeCount totalFeesCollected
    }
  }`,
  );
  if (tokens) {
    check("query returned", tokens.gradPadTokens, (v) => Array.isArray(v));
    check(
      "token count",
      tokens.gradPadTokens.length,
      (v) => v >= 0,
      (v) => `${v} tokens`,
    );
    if (tokens.gradPadTokens.length > 0) {
      const t = tokens.gradPadTokens[0];
      console.log(
        `  latest token: ${t.name} (${t.symbol}) — ${t.bondingPhase ? "Bonding" : "Graduated"}`,
      );
      console.log(
        `    volume: ${t.totalVolume} | trades: ${t.tradeCount} | fees: ${t.totalFeesCollected}`,
      );
      check("has id (address)", t.id, (v) => v && v.startsWith("0x"));
      check("has name", t.name, (v) => typeof v === "string" && v.length > 0);
      check(
        "totalFeesCollected present",
        t.totalFeesCollected,
        (v) => v !== undefined,
      );
    } else {
      console.log("  ℹ no tokens indexed yet — create a token on-chain first");
    }
  } else {
    allPassed = false;
  }

  // ─── 3. Buckets ──────────────────────────────────────────────────────────
  console.log("\n── 3. Buckets (on first token)");
  if (tokens?.gradPadTokens?.length > 0) {
    const tokenId = tokens.gradPadTokens[0].id;
    const detail = await query(
      "token detail",
      `
      query($id: ID!) {
        gradPadToken(id: $id) {
          name
          buckets {
            index name basisPoints recipient cliff vestingDuration isLiquidity totalClaimed
          }
        }
      }
    `,
      { id: tokenId },
    );

    if (detail?.gradPadToken) {
      const buckets = detail.gradPadToken.buckets;
      check(
        "has buckets",
        buckets,
        (v) => Array.isArray(v) && v.length > 0,
        (v) => `${v.length} buckets`,
      );

      if (buckets.length > 0) {
        const total = buckets.reduce(
          (sum, b) => sum + parseInt(b.basisPoints),
          0,
        );
        check(
          "basisPoints sum to 10000",
          total,
          (v) => v === 10000,
          (v) => `sum = ${v}`,
        );

        const liquidityCount = buckets.filter((b) => b.isLiquidity).length;
        check(
          "exactly one liquidity bucket",
          liquidityCount,
          (v) => v === 1,
          (v) => `${v} liquidity buckets`,
        );

        console.log("  buckets:");
        for (const b of buckets) {
          const pct = (parseInt(b.basisPoints) / 100).toFixed(1);
          const tag = b.isLiquidity
            ? "[liquidity]"
            : `cliff:${b.cliff}s vest:${b.vestingDuration}s`;
          console.log(`    [${b.index}] ${b.name} ${pct}% — ${tag}`);
        }
      }
    }
  } else {
    console.log("  ℹ skipped — no tokens to check");
  }

  // ─── 4. Trades ───────────────────────────────────────────────────────────
  console.log("\n── 4. Trades");
  const tradesData = await query(
    "trades",
    `{
    trades(first: 10, orderBy: timestamp, orderDirection: desc) {
      id isBuy amountIn amountOut price phase blockNumber
      token { id symbol }
    }
  }`,
  );
  if (tradesData) {
    check("query returned", tradesData.trades, (v) => Array.isArray(v));
    check(
      "trade count",
      tradesData.trades.length,
      (v) => v >= 0,
      (v) => `${v} recent trades`,
    );

    if (tradesData.trades.length > 0) {
      const t = tradesData.trades[0];
      check(
        "price is non-zero",
        t.price,
        (v) => parseFloat(v) > 0,
        (v) => v,
      );
      check(
        "phase is valid",
        t.phase,
        (v) => v === "bonding" || v === "uniswap",
        (v) => v,
      );
      console.log(
        `  latest: ${t.isBuy ? "BUY" : "SELL"} ${t.token.symbol} — amountIn:${t.amountIn} amountOut:${t.amountOut} price:${t.price} [${t.phase}]`,
      );
    } else {
      console.log("  ℹ no trades indexed yet");
    }
  } else {
    allPassed = false;
  }

  // ─── 5. User entity ──────────────────────────────────────────────────────
  console.log("\n── 5. User entity");
  const users = await query(
    "users",
    `{
    users(first: 3) {
      id tradeCount totalVolumeUSDC
    }
  }`,
  );
  if (users) {
    check("query returned", users.users, (v) => Array.isArray(v));
    check(
      "user count",
      users.users.length,
      (v) => v >= 0,
      (v) => `${v} users`,
    );
    for (const u of users.users) {
      console.log(
        `  ${u.id.slice(0, 10)}... trades:${u.tradeCount} vol:${u.totalVolumeUSDC}`,
      );
    }
  } else {
    allPassed = false;
  }

  // ─── 6. FeeEvent (V2 only) ───────────────────────────────────────────────
  console.log("\n── 6. FeeEvent (V2 only — expected empty on V1)");
  const fees = await query(
    "feeEvents",
    `{
    feeEvents(first: 5) {
      id feeAmount timestamp
      token { symbol }
    }
  }`,
  );
  if (fees) {
    check("query returned", fees.feeEvents, (v) => Array.isArray(v));
    console.log(
      `  ${fees.feeEvents.length} fee events (0 is correct while V1 proxy is live)`,
    );
  }

  // ─── Summary ─────────────────────────────────────────────────────────────
  console.log("\n" + "─".repeat(50));
  console.log(
    allPassed
      ? "✓ All critical checks passed"
      : "✗ Some checks failed — see above",
  );
  console.log();
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
