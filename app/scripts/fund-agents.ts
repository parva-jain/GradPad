#!/usr/bin/env tsx
/**
 * Generates 6 fresh agent wallets and funds each with 0.0005 ETH from your
 * main wallet. Then writes SEED_PRIVATE_KEYS to .env.local automatically.
 *
 * Setup:
 *   Add to .env.local:
 *     MAIN_PRIVATE_KEY=0x...   (your wallet with Base ETH)
 *
 * Run:
 *   npm run fund
 */

import {
  createPublicClient,
  createWalletClient,
  http,
  parseEther,
  formatEther,
} from "viem";
import { base } from "viem/chains";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";
import * as fs from "fs";
import * as path from "path";

const ENV_PATH = path.resolve(process.cwd(), ".env.local");
const AMOUNT = parseEther("0.0001"); // per agent wallet
const COUNT = 6;

// ─── Load .env.local ──────────────────────────────────────────────────────────

function loadEnvLocal(): Record<string, string> {
  const entries: Record<string, string> = {};
  if (!fs.existsSync(ENV_PATH)) return entries;
  for (const line of fs.readFileSync(ENV_PATH, "utf-8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    entries[trimmed.slice(0, eq).trim()] = trimmed.slice(eq + 1).trim();
  }
  return entries;
}

function saveEnvLocal(entries: Record<string, string>) {
  // Re-read raw file to preserve comments, only replace/add SEED_PRIVATE_KEYS
  const raw = fs.existsSync(ENV_PATH) ? fs.readFileSync(ENV_PATH, "utf-8") : "";
  const lines = raw.split("\n");

  const keyLine = `SEED_PRIVATE_KEYS=${entries["SEED_PRIVATE_KEYS"]}`;
  const idx = lines.findIndex((l) => l.startsWith("SEED_PRIVATE_KEYS="));

  if (idx !== -1) {
    lines[idx] = keyLine;
  } else {
    lines.push("", keyLine);
  }

  fs.writeFileSync(ENV_PATH, lines.join("\n"));
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  console.log("\n" + "═".repeat(54));
  console.log("  GradPad Agent Fund Script");
  console.log(
    `  Generating ${COUNT} wallets · ${formatEther(AMOUNT)} ETH each`,
  );
  console.log("═".repeat(54) + "\n");

  const env = loadEnvLocal();
  Object.assign(process.env, env);

  const mainKey = process.env.MAIN_PRIVATE_KEY;
  if (!mainKey) {
    console.error("❌  Missing MAIN_PRIVATE_KEY in .env.local");
    process.exit(1);
  }

  const funder = privateKeyToAccount(mainKey as `0x${string}`);
  const pub = createPublicClient({
    chain: base,
    transport: http("https://mainnet.base.org"),
  });
  const funderClient = createWalletClient({
    account: funder,
    chain: base,
    transport: http("https://mainnet.base.org"),
  });

  // Check funder balance
  const funderBal = await pub.getBalance({ address: funder.address });
  const totalNeeded = AMOUNT * BigInt(COUNT);
  console.log(`  Funder: ${funder.address}`);
  console.log(`  Balance: ${formatEther(funderBal)} ETH`);
  console.log(`  Sending: ${formatEther(totalNeeded)} ETH total + gas\n`);

  if (funderBal < totalNeeded) {
    console.error(
      `❌  Insufficient balance — need at least ${formatEther(totalNeeded)} ETH`,
    );
    process.exit(1);
  }

  // Generate agent keys and fund them
  const agentKeys: string[] = [];

  for (let i = 0; i < COUNT; i++) {
    const key = generatePrivateKey();
    const account = privateKeyToAccount(key);
    agentKeys.push(key);

    console.log(`  Funding agent ${i + 1}/6: ${account.address}`);
    const hash = await funderClient.sendTransaction({
      to: account.address,
      value: AMOUNT,
    });
    await pub.waitForTransactionReceipt({ hash });
    console.log(
      `    ✅  Sent ${formatEther(AMOUNT)} ETH  (tx: ${hash.slice(0, 18)}...)`,
    );
  }

  // Write keys to .env.local
  const envEntries = loadEnvLocal();
  envEntries["SEED_PRIVATE_KEYS"] = agentKeys.join(",");
  saveEnvLocal(envEntries);

  console.log("\n" + "═".repeat(54));
  console.log("  Done! SEED_PRIVATE_KEYS written to .env.local");
  console.log("  Run `npm run seed` to populate GradPad with data.");
  console.log("═".repeat(54) + "\n");
}

main().catch((err) => {
  console.error("\n❌  Fatal:", err);
  process.exit(1);
});
