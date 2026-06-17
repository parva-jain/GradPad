#!/usr/bin/env tsx
/**
 * GradPad AI Agent Seeder
 *
 * Seeds GradPad with 12 realistic tokens and autonomous agent-driven trading.
 * Six AI agents with distinct personalities use Groq (llama-3.3-70b) to make
 * buy/sell decisions — showcasing the AIxCrypto primitive of autonomous
 * wallets with LLM cognition.
 *
 * Setup:
 *   1. Run `npm run fund` to generate 6 agent wallets and fund them with ETH
 *   2. Add to .env.local:
 *        GROQ_API_KEY=gsk_...
 *   3. npm run seed
 */

import {
  createPublicClient,
  createWalletClient,
  http,
  parseUnits,
  formatUnits,
  parseEther,
  formatEther,
  keccak256,
  encodePacked,
  maxUint256,
  parseEventLogs,
  type Address,
  type Hash,
} from 'viem'
import { base } from 'viem/chains'
import { privateKeyToAccount, type PrivateKeyAccount } from 'viem/accounts'
import Groq from 'groq-sdk'
import * as fs from 'fs'
import * as path from 'path'

// ─── Load .env.local ──────────────────────────────────────────────────────────

function loadEnvLocal() {
  const envPath = path.resolve(process.cwd(), '.env.local')
  if (!fs.existsSync(envPath)) return
  for (const line of fs.readFileSync(envPath, 'utf-8').split('\n')) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue
    const eq = trimmed.indexOf('=')
    if (eq === -1) continue
    const key = trimmed.slice(0, eq).trim()
    const val = trimmed.slice(eq + 1).trim()
    if (!process.env[key]) process.env[key] = val
  }
}
loadEnvLocal()

const GROQ_API_KEY = process.env.GROQ_API_KEY
const RAW_KEYS     = process.env.SEED_PRIVATE_KEYS

if (!GROQ_API_KEY) { console.error('❌  Missing GROQ_API_KEY in .env.local'); process.exit(1) }
if (!RAW_KEYS)     { console.error('❌  Missing SEED_PRIVATE_KEYS in .env.local — run `npm run fund` first'); process.exit(1) }

// ─── Addresses ────────────────────────────────────────────────────────────────

const FACTORY = '0xc2aae1bdfb4d178b8a0d72750e10ffb98813948a' as Address
const USDC    = '0x7b851635eea924e8501e733909fcf91ab1b98348' as Address
const ZERO    = '0x0000000000000000000000000000000000000000' as Address

const GRADUATING_INDICES   = [0, 1]
const GRAD_THRESHOLD       = parseUnits('1200',   6)
const GRAD_VIRTUAL_RESERVE = parseUnits('300',    6)
const NORM_THRESHOLD       = parseUnits('5000', 6)
const NORM_VIRTUAL_RESERVE = parseUnits('1500', 6)

// ─── ABIs ─────────────────────────────────────────────────────────────────────

const FACTORY_EVENTS_ABI = [
  {
    name: 'GPTokenCreated', type: 'event',
    inputs: [
      { name: 'token',       type: 'address', indexed: true  },
      { name: 'creator',     type: 'address', indexed: true  },
      { name: 'name',        type: 'string',  indexed: false },
      { name: 'symbol',      type: 'string',  indexed: false },
      { name: 'totalSupply', type: 'uint256', indexed: false },
    ],
  },
] as const

const TOKEN_ABI = [
  {
    name: 'bondingPhase', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ type: 'bool' }],
  },
] as const

const FACTORY_ABI = [
  {
    name: 'createGPToken', type: 'function', stateMutability: 'nonpayable',
    inputs: [
      { name: 'name',        type: 'string'  },
      { name: 'symbol',      type: 'string'  },
      { name: 'totalSupply', type: 'uint256' },
      {
        name: '_buckets', type: 'tuple[]',
        components: [
          { name: 'name',            type: 'string'  },
          { name: 'basisPoints',     type: 'uint256' },
          { name: 'recipient',       type: 'address' },
          { name: 'cliff',           type: 'uint256' },
          { name: 'vestingDuration', type: 'uint256' },
          { name: 'isLiquidity',     type: 'bool'    },
        ],
      },
      { name: 'graduationThreshold_', type: 'uint256' },
      { name: 'virtualAssetReserve_', type: 'uint256' },
      { name: 'salt',                 type: 'bytes32' },
    ],
    outputs: [{ type: 'address' }],
  },
  {
    name: 'buyGPToken', type: 'function', stateMutability: 'nonpayable',
    inputs: [
      { name: 'token',         type: 'address' },
      { name: 'assetAmountIn', type: 'uint256' },
      { name: 'to',            type: 'address' },
      { name: 'minTokensOut',  type: 'uint256' },
    ],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'sellGPToken', type: 'function', stateMutability: 'nonpayable',
    inputs: [
      { name: 'token',         type: 'address' },
      { name: 'tokenAmountIn', type: 'uint256' },
      { name: 'to',            type: 'address' },
      { name: 'minAssetOut',   type: 'uint256' },
    ],
    outputs: [{ type: 'uint256' }],
  },
] as const

const ERC20_ABI = [
  {
    name: 'mint', type: 'function', stateMutability: 'nonpayable',
    inputs: [{ name: 'amount', type: 'uint256' }], outputs: [],
  },
  {
    name: 'approve', type: 'function', stateMutability: 'nonpayable',
    inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }],
    outputs: [{ type: 'bool' }],
  },
  {
    name: 'allowance', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'balanceOf', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
] as const

// ─── Agent personalities ───────────────────────────────────────────────────────

interface AgentDef {
  name: string
  emoji: string
  personality: string
  bias: 'meme' | 'protocol' | 'any'
  maxSpendPct: number
  takesProfits: boolean
}

const AGENT_DEFS: AgentDef[] = [
  {
    name: 'DegenBot',
    emoji: '🎲',
    personality:
      'You are DegenBot, an unhinged meme-token maximalist. You FOMO hard, buy in large, never sell, and hype everything. Your reasoning is chaotic, passionate, and full of crypto slang.',
    bias: 'meme',
    maxSpendPct: 0.85,
    takesProfits: false,
  },
  {
    name: 'AlphaSeeker',
    emoji: '🔍',
    personality:
      'You are AlphaSeeker, a systematic AI agent hunting early-stage value. You prefer protocol tokens with structured tokenomics and a clear use case. Your reasoning is analytical and thesis-driven.',
    bias: 'protocol',
    maxSpendPct: 0.5,
    takesProfits: false,
  },
  {
    name: 'MomentumTrader',
    emoji: '📈',
    personality:
      'You are MomentumTrader, a trend-following agent. You only enter tokens that already show buy volume. You take partial profits after rides. Your reasoning cites price action and momentum signals.',
    bias: 'any',
    maxSpendPct: 0.55,
    takesProfits: true,
  },
  {
    name: 'WhaleBot',
    emoji: '🐋',
    personality:
      'You are WhaleBot, an agent with a concentrated high-conviction strategy. You focus on 2-3 tokens you believe in deeply and size up aggressively. Your reasoning is confident and deliberate.',
    bias: 'any',
    maxSpendPct: 0.75,
    takesProfits: false,
  },
  {
    name: 'FlipperAI',
    emoji: '🔄',
    personality:
      'You are FlipperAI, a short-term profit-taker. You buy small amounts, let price appreciate, then flip for gains. You are selective — only tokens with interesting narratives. Your reasoning is tactical.',
    bias: 'any',
    maxSpendPct: 0.3,
    takesProfits: true,
  },
  {
    name: 'BaseNative',
    emoji: '🔵',
    personality:
      'You are BaseNative, a true believer in the Base ecosystem. You support Base-native DeFi and AI infrastructure projects. You are bullish and community-oriented. Your reasoning highlights ecosystem synergies.',
    bias: 'protocol',
    maxSpendPct: 0.65,
    takesProfits: false,
  },
]

// ─── Types ────────────────────────────────────────────────────────────────────

interface TokenConcept {
  name: string
  symbol: string
  description: string
  type: 'meme' | 'protocol'
  tagline: string
}

interface CreatedToken extends TokenConcept {
  address: Address
  willGraduate: boolean
}

interface AgentWallet {
  account: PrivateKeyAccount
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  client: any  // viem WalletClient
  def: AgentDef
  usdcBalance: bigint
  boughtTokens: Set<Address>
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function log(emoji: string, msg: string) {
  console.log(`  ${emoji}  ${msg}`)
}

function hr(label: string) {
  console.log(`\n${'─'.repeat(50)}`)
  console.log(`  ${label}`)
  console.log('─'.repeat(50))
}

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms))

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function waitTx(pub: any, hash: Hash, label: string) {
  const receipt = await pub.waitForTransactionReceipt({ hash })
  if (receipt.status === 'reverted') throw new Error(`Reverted: ${label}`)
  return receipt
}

// ─── Groq helpers ──────────────────────────────────────────────────────────────

async function generateConcepts(groq: Groq, count: number): Promise<TokenConcept[]> {
  log('🤖', `Generating ${count} token concepts via Groq...`)

  const res = await groq.chat.completions.create({
    model: 'llama-3.3-70b-versatile',
    temperature: 0.95,
    response_format: { type: 'json_object' },
    messages: [
      {
        role: 'system',
        content: `You create realistic, creative crypto token concepts for a Base chain launchpad in 2026.

MEME tokens: internet-culture-driven, animal/food/vibe themed, no utility claims, names like real memes
PROTOCOL tokens: DeFi, AI agents, yield, RWA, cross-chain infra — real-sounding projects

Return ONLY valid JSON. No markdown, no commentary.`,
      },
      {
        role: 'user',
        content: `Generate exactly ${count} token concepts. Make ~40% meme and ~60% protocol.
Each must feel like a real project someone would actually launch in 2026.

JSON format (return ONLY this):
{
  "tokens": [
    {
      "name": "2-4 word project name",
      "symbol": "3-5 uppercase letters — must be unique across the list",
      "description": "1-2 sentences — reads like an actual project description",
      "type": "meme or protocol",
      "tagline": "punchy phrase under 8 words"
    }
  ]
}`,
      },
    ],
  })

  const raw = res.choices[0].message.content ?? '{}'
  const parsed = JSON.parse(raw)
  const tokens: TokenConcept[] = (parsed.tokens ?? []).slice(0, count)

  const seen = new Set<string>()
  const deduped = tokens.filter(t => {
    if (seen.has(t.symbol)) return false
    seen.add(t.symbol)
    return true
  })

  log('✅', `Got ${deduped.length} concepts: ${deduped.map(t => t.symbol).join(', ')}`)
  return deduped
}

interface BuyDecision {
  action: 'buy' | 'skip'
  amount: number
  reasoning: string
}

async function askBuyDecision(
  groq: Groq,
  agent: AgentDef,
  token: TokenConcept,
  availableUsdc: number,
  tradeCount: number,
): Promise<BuyDecision> {
  const maxSpend = Math.floor(availableUsdc * agent.maxSpendPct)
  const minSpend = 50
  if (maxSpend < minSpend) return { action: 'skip', amount: 0, reasoning: 'Balance too low' }

  const res = await groq.chat.completions.create({
    model: 'llama-3.3-70b-versatile',
    temperature: 0.75,
    response_format: { type: 'json_object' },
    messages: [
      {
        role: 'system',
        content: `${agent.personality}

You trade on GradPad, a Base chain launchpad. Tokens move from bonding curve → Uniswap when they hit a volume threshold.
You have ${availableUsdc.toFixed(0)} mUSDC. Stay in character.
Return ONLY valid JSON.`,
      },
      {
        role: 'user',
        content: `Token: ${token.name} (${token.symbol})
Type: ${token.type}
"${token.description}"
Tagline: "${token.tagline}"
Existing trades on this token: ${tradeCount}

Buy or skip? If buying: spend between ${minSpend} and ${maxSpend} mUSDC.

JSON: {"action":"buy"|"skip","amount":<number>,"reasoning":"<one sentence in character>"}`,
      },
    ],
  })

  try {
    const d = JSON.parse(res.choices[0].message.content ?? '{}') as BuyDecision
    if (d.action === 'buy') {
      d.amount = Math.max(minSpend, Math.min(maxSpend, Number(d.amount) || minSpend))
    }
    return d
  } catch {
    return { action: 'skip', amount: 0, reasoning: 'Parse error' }
  }
}

interface SellDecision {
  action: 'sell' | 'hold'
  percentage: number
  reasoning: string
}

async function askSellDecision(groq: Groq, agent: AgentDef, token: TokenConcept): Promise<SellDecision> {
  const res = await groq.chat.completions.create({
    model: 'llama-3.3-70b-versatile',
    temperature: 0.65,
    response_format: { type: 'json_object' },
    messages: [
      { role: 'system', content: `${agent.personality}\nReturn ONLY valid JSON.` },
      {
        role: 'user',
        content: `You hold a ${token.symbol} position you bought earlier. Do you want to sell some for profit?

JSON: {"action":"sell"|"hold","percentage":<10-50 if selling, else 0>,"reasoning":"<one sentence in character>"}`,
      },
    ],
  })

  try {
    return JSON.parse(res.choices[0].message.content ?? '{}') as SellDecision
  } catch {
    return { action: 'hold', percentage: 0, reasoning: 'Holding' }
  }
}

// ─── Contract actions ──────────────────────────────────────────────────────────

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function mintUsdc(agent: AgentWallet, pub: any) {
  log(agent.def.emoji, `${agent.def.name} minting 1,000 mUSDC...`)
  const hash = await agent.client.writeContract({
    address: USDC, abi: ERC20_ABI, functionName: 'mint',
    args: [parseUnits('1000', 6)], chain: base,
  })
  await waitTx(pub, hash, 'mint')
  agent.usdcBalance = parseUnits('1000', 6)
  log('✅', `${agent.def.name} balance: 1000 mUSDC`)
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function ensureUsdcApproved(agent: AgentWallet, pub: any, amount: bigint) {
  const allowance = await pub.readContract({
    address: USDC, abi: ERC20_ABI, functionName: 'allowance',
    args: [agent.account.address, FACTORY],
  }) as bigint
  if (allowance < amount) {
    const hash = await agent.client.writeContract({
      address: USDC, abi: ERC20_ABI, functionName: 'approve',
      args: [FACTORY, maxUint256], chain: base,
    })
    await waitTx(pub, hash, 'approve USDC')
    await sleep(3_000) // Allow RPC nodes to sync the approval before next tx
  }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function createToken(agent: AgentWallet, pub: any, concept: TokenConcept, willGraduate: boolean): Promise<Address> {
  const buckets = concept.type === 'protocol'
    ? [
        { name: 'Liquidity', basisPoints: BigInt(6000), recipient: ZERO,                 cliff: BigInt(0),           vestingDuration: BigInt(0),           isLiquidity: true  },
        { name: 'Team',      basisPoints: BigInt(2000), recipient: agent.account.address, cliff: BigInt(365 * 86400), vestingDuration: BigInt(730 * 86400), isLiquidity: false },
        { name: 'Investors', basisPoints: BigInt(1000), recipient: agent.account.address, cliff: BigInt(180 * 86400), vestingDuration: BigInt(365 * 86400), isLiquidity: false },
        { name: 'Treasury',  basisPoints: BigInt(1000), recipient: agent.account.address, cliff: BigInt(0),           vestingDuration: BigInt(0),           isLiquidity: false },
      ]
    : [
        { name: 'Liquidity', basisPoints: BigInt(10000), recipient: ZERO, cliff: BigInt(0), vestingDuration: BigInt(0), isLiquidity: true },
      ]

  const salt = keccak256(encodePacked(
    ['address', 'string', 'uint256'],
    [agent.account.address, concept.name, BigInt(Date.now())]
  ))

  log(agent.def.emoji, `${agent.def.name} deploying ${concept.symbol} — "${concept.tagline}"`)

  const hash = await agent.client.writeContract({
    address: FACTORY, abi: FACTORY_ABI, functionName: 'createGPToken',
    args: [
      concept.name, concept.symbol,
      parseEther('1000000000'),
      buckets,
      willGraduate ? GRAD_THRESHOLD       : NORM_THRESHOLD,
      willGraduate ? GRAD_VIRTUAL_RESERVE : NORM_VIRTUAL_RESERVE,
      salt,
    ],
    chain: base,
  })
  const receipt = await waitTx(pub, hash, `create ${concept.symbol}`)

  // Parse the token address from the GPTokenCreated event — more reliable than
  // reading allTokens[lenBefore] which can fail if the factory reverts for
  // unrelated state reads.
  const logs = parseEventLogs({ abi: FACTORY_EVENTS_ABI, logs: receipt.logs, eventName: 'GPTokenCreated' })
  if (logs.length === 0) throw new Error('GPTokenCreated event not found in receipt')
  const addr = logs[0].args.token as Address

  log('✅', `${concept.symbol} → ${addr}${willGraduate ? ' [graduation target 🎓]' : ''}`)
  return addr
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function buyToken(agent: AgentWallet, pub: any, token: CreatedToken, usdcAmount: bigint) {
  if (usdcAmount > agent.usdcBalance) usdcAmount = agent.usdcBalance
  if (usdcAmount < parseUnits('10', 6)) return

  await ensureUsdcApproved(agent, pub, usdcAmount)
  const hash = await agent.client.writeContract({
    address: FACTORY, abi: FACTORY_ABI, functionName: 'buyGPToken',
    args: [token.address, usdcAmount, agent.account.address, BigInt(0)],
    chain: base,
  })
  await waitTx(pub, hash, `buy ${token.symbol}`)
  agent.usdcBalance -= usdcAmount
  agent.boughtTokens.add(token.address)
  log('💸', `${agent.def.name} bought ${formatUnits(usdcAmount, 6)} mUSDC of ${token.symbol} (left: ${formatUnits(agent.usdcBalance, 6)})`)
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function sellToken(agent: AgentWallet, pub: any, token: CreatedToken, percentage: number) {
  const bal = await pub.readContract({
    address: token.address, abi: ERC20_ABI, functionName: 'balanceOf',
    args: [agent.account.address],
  }) as bigint
  if (bal === BigInt(0)) return

  const sellAmt = (bal * BigInt(Math.min(50, Math.max(10, percentage)))) / BigInt(100)
  if (sellAmt === BigInt(0)) return

  const allowance = await pub.readContract({
    address: token.address, abi: ERC20_ABI, functionName: 'allowance',
    args: [agent.account.address, FACTORY],
  }) as bigint

  if (allowance < sellAmt) {
    const ah = await agent.client.writeContract({
      address: token.address, abi: ERC20_ABI, functionName: 'approve',
      args: [FACTORY, maxUint256], chain: base,
    })
    await waitTx(pub, ah, `approve ${token.symbol}`)
  }

  const hash = await agent.client.writeContract({
    address: FACTORY, abi: FACTORY_ABI, functionName: 'sellGPToken',
    args: [token.address, sellAmt, agent.account.address, BigInt(0)],
    chain: base,
  })
  await waitTx(pub, hash, `sell ${token.symbol}`)
  log('💰', `${agent.def.name} sold ${percentage}% of ${token.symbol} position`)
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  console.log('\n' + '═'.repeat(54))
  console.log('  GradPad AI Agent Seeder')
  console.log('  6 agents · 12 tokens · Groq llama-3.3-70b')
  console.log('═'.repeat(54))

  const keys = RAW_KEYS!.split(',').map(k => k.trim()).filter(Boolean)
  if (keys.length < 3) {
    console.error('\n❌  Need at least 3 private keys in SEED_PRIVATE_KEYS\n')
    process.exit(1)
  }

  const groq = new Groq({ apiKey: GROQ_API_KEY })
  const pub  = createPublicClient({ chain: base, transport: http('https://mainnet.base.org') })

  const agents: AgentWallet[] = keys.slice(0, 6).map((key, i) => {
    const account = privateKeyToAccount(key as `0x${string}`)
    const client  = createWalletClient({ account, chain: base, transport: http('https://mainnet.base.org') })
    const def     = AGENT_DEFS[i % AGENT_DEFS.length]
    console.log(`  ${def.emoji}  ${def.name.padEnd(16)} ${account.address}`)
    return { account, client, def, usdcBalance: BigInt(0), boughtTokens: new Set<Address>() }
  })

  const outPath    = path.resolve(process.cwd(), 'scripts/seeded-tokens.json')
  const isResuming = fs.existsSync(outPath)
  let createdTokens: CreatedToken[] = []

  // ── Phase 1: Mint mUSDC — always runs ───────────────────────────────────────
  hr('Phase 1 · Minting mUSDC')

  for (const agent of agents) {
    try {
      await mintUsdc(agent, pub)
    } catch {
      const bal = await pub.readContract({
        address: USDC, abi: ERC20_ABI, functionName: 'balanceOf',
        args: [agent.account.address],
      }) as bigint
      agent.usdcBalance = bal
      log('ℹ️ ', `${agent.def.name} already minted today — balance: ${formatUnits(bal, 6)} mUSDC`)
    }
    await sleep(2_000)
  }

  if (isResuming) {
    createdTokens = JSON.parse(fs.readFileSync(outPath, 'utf-8')) as CreatedToken[]
    log('📂', `Resuming — loaded ${createdTokens.length} previously deployed tokens (skipping Phases 2-3)`)
  } else {
    // ── Phase 2: Generate token concepts ────────────────────────────────────────
    hr('Phase 2 · Generating Token Concepts')

    const concepts = await generateConcepts(groq, 12)
    if (concepts.length < 6) {
      console.error('\n❌  Groq returned too few concepts — retry\n'); process.exit(1)
    }

    // ── Phase 3: Create tokens ───────────────────────────────────────────────────
    hr('Phase 3 · Deploying Tokens')

    for (let i = 0; i < concepts.length; i++) {
      const concept      = concepts[i]
      const willGraduate = GRADUATING_INDICES.includes(i)
      const creator      = agents[i % agents.length]

      try {
        const address = await createToken(creator, pub, concept, willGraduate)
        createdTokens.push({ ...concept, address, willGraduate })
        await sleep(3_000)
      } catch (err) {
        log('❌', `Failed to deploy ${concept.symbol}: ${String(err).slice(0, 200)}`)
      }
    }

    fs.writeFileSync(outPath, JSON.stringify(createdTokens, null, 2))
    log('💾', `Token list saved → scripts/seeded-tokens.json`)
  }

  const graduating = createdTokens.filter(t => t.willGraduate)
  const bonding    = createdTokens.filter(t => !t.willGraduate)

  // ── Phase 4: Graduation push ─────────────────────────────────────────────────
  hr('Phase 4 · Graduation Push')

  const gradAgents = agents.slice(0, 3)

  for (const token of graduating) {
    const stillBonding = await pub.readContract({
      address: token.address, abi: TOKEN_ABI, functionName: 'bondingPhase',
    }) as boolean
    if (!stillBonding) {
      log('⏭️ ', `${token.symbol} already graduated — skipping push`)
      continue
    }

    log('🎓', `Pushing ${token.symbol} toward graduation (${formatUnits(GRAD_THRESHOLD, 6)} mUSDC target)...`)
    for (const agent of gradAgents) {
      const pushAmt = (agent.usdcBalance * BigInt(55)) / BigInt(100)
      const capped  = pushAmt > parseUnits('450', 6) ? parseUnits('450', 6) : pushAmt
      if (capped < parseUnits('50', 6)) continue
      try {
        await buyToken(agent, pub, token, capped)
        await sleep(3_000)
      } catch (err) {
        log('❌', `Graduation buy failed: ${String(err).slice(0, 200)}`)
      }
    }
  }

  // ── Phase 5: Bonding-phase discovery ─────────────────────────────────────────
  hr('Phase 5 · Bonding Phase Discovery')

  const tradeCounts: Record<Address, number> = {}

  async function doTrade(agent: AgentWallet, token: CreatedToken) {
    const usdcNum = parseFloat(formatUnits(agent.usdcBalance, 6))
    if (usdcNum < 50) return

    const decision = await askBuyDecision(groq, agent.def, token, usdcNum, tradeCounts[token.address] ?? 0)
    log(agent.def.emoji, `${agent.def.name} → ${token.symbol}: "${decision.reasoning}"`)

    if (decision.action === 'skip') {
      log('⏭️ ', `${agent.def.name} skips ${token.symbol}`)
      return
    }

    const usdcIn = parseUnits(String(decision.amount), 6)
    await buyToken(agent, pub, token, usdcIn)
    tradeCounts[token.address] = (tradeCounts[token.address] ?? 0) + 1
    await sleep(2_500)
  }

  log('📊', 'Round A — Early discovery (bias-matched)...')
  for (const agent of agents) {
    const targets = bonding
      .filter(t => agent.def.bias === 'any' || t.type === agent.def.bias || Math.random() > 0.45)
      .slice(0, 3)
    for (const t of targets) {
      try { await doTrade(agent, t) } catch (err) {
        log('❌', `Trade failed (${agent.def.name} → ${t.symbol}): ${String(err).slice(0, 200)}`)
      }
    }
  }

  log('📊', 'Round B — Momentum (tokens with ≥2 trades)...')
  for (const agent of agents) {
    const hotTokens = bonding.filter(t => (tradeCounts[t.address] ?? 0) >= 2).slice(0, 2)
    for (const t of hotTokens) {
      try { await doTrade(agent, t) } catch (err) {
        log('❌', `Trade failed (${agent.def.name} → ${t.symbol}): ${String(err).slice(0, 200)}`)
      }
    }
  }

  log('📊', 'Round C — Profit taking...')
  for (const agent of agents.filter(a => a.def.takesProfits)) {
    const held = bonding.filter(t => agent.boughtTokens.has(t.address)).slice(0, 2)
    for (const token of held) {
      try {
        const sd = await askSellDecision(groq, agent.def, token)
        log(agent.def.emoji, `${agent.def.name} sell on ${token.symbol}: "${sd.reasoning}"`)
        if (sd.action === 'sell') {
          await sellToken(agent, pub, token, sd.percentage || 30)
          await sleep(2_500)
        }
      } catch (err) {
        log('❌', `Sell failed: ${String(err).slice(0, 200)}`)
      }
    }
  }

  log('📊', 'Round D — Final spread...')
  for (const agent of agents) {
    if (agent.usdcBalance < parseUnits('50', 6)) continue
    const rand = bonding[Math.floor(Math.random() * bonding.length)]
    if (!rand) continue
    const amt = (agent.usdcBalance * BigInt(40)) / BigInt(100)
    if (amt >= parseUnits('50', 6)) {
      try { await buyToken(agent, pub, rand, amt); await sleep(2_000) } catch (err) {
        log('❌', `Random buy failed (${agent.def.name} → ${rand.symbol}): ${String(err).slice(0, 200)}`)
      }
    }
  }

  // ── Summary ──────────────────────────────────────────────────────────────────
  console.log('\n' + '═'.repeat(54))
  console.log('  SEED COMPLETE')
  console.log('═'.repeat(54))

  console.log(`\n  Graduated tokens (${graduating.length}):`)
  for (const t of graduating) {
    console.log(`    🎓  ${t.symbol.padEnd(8)} ${t.name.padEnd(28)} ${t.address}`)
  }

  console.log(`\n  Bonding phase tokens (${bonding.length}):`)
  for (const t of bonding) {
    const trades = tradeCounts[t.address] ?? 0
    console.log(`    📈  ${t.symbol.padEnd(8)} ${t.name.padEnd(28)} ${trades} trades  ${t.address}`)
  }

  console.log('\n  Token list: scripts/seeded-tokens.json')
  console.log('  Note: subgraph indexing takes ~1 min — tokens appear shortly.\n')
}

main().catch(err => {
  console.error('\n❌  Fatal:', err)
  process.exit(1)
})
