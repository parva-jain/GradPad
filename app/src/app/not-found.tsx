import Link from 'next/link'

export default function NotFound() {
  return (
    <main
      className="flex flex-col items-center justify-center min-h-screen gap-6"
      style={{ background: '#0c0a06' }}
    >
      <div
        className="fixed inset-0 pointer-events-none"
        style={{
          background:
            'radial-gradient(ellipse 50% 40% at 50% 30%, rgba(251,191,36,0.06) 0%, transparent 70%)',
        }}
      />

      <div className="relative text-center space-y-3">
        <p
          className="text-8xl font-black tracking-tight"
          style={{
            background: 'linear-gradient(90deg, #fbbf24, #f59e0b)',
            WebkitBackgroundClip: 'text',
            WebkitTextFillColor: 'transparent',
          }}
        >
          404
        </p>
        <h1 className="text-2xl font-bold text-white">Page not found</h1>
        <p className="text-sm" style={{ color: '#6b7280' }}>
          This token hasn&apos;t graduated yet — or maybe it never existed.
        </p>
      </div>

      <Link
        href="/"
        className="relative px-5 py-2.5 rounded-xl text-sm font-semibold transition-colors"
        style={{
          background: 'rgba(251,191,36,0.1)',
          border: '1px solid rgba(251,191,36,0.2)',
          color: '#fbbf24',
        }}
      >
        Back to Discover
      </Link>
    </main>
  )
}
