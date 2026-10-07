import { useEffect, useState } from 'react';

// Set at image build time (see Dockerfile), so you can see which frontend version is deployed.
const webVersion = import.meta.env.VITE_APP_VERSION ?? 'dev';

export default function App() {
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);

  // The browser calls a relative URL. nginx (in the same pod as this page)
  // forwards /api/* to the .NET API service, so no CORS setup is needed.
  function load() {
    setError(null);
    fetch('/api/hello')
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
      })
      .then(setData)
      .catch((err) => setError(err.message));
  }

  useEffect(load, []);

  return (
    <main style={{ fontFamily: 'system-ui, sans-serif', maxWidth: 640, margin: '3rem auto', padding: '0 1rem' }}>
      <h1>Hello Argo CD</h1>
      <p>Frontend version: <code>{webVersion}</code></p>

      <h2>Response from the .NET API</h2>
      {error && <p style={{ color: 'crimson' }}>Could not reach the API: {error}</p>}
      {!error && !data && <p>Loading…</p>}
      {data && (
        <dl>
          <dt>Message</dt><dd>{data.message}</dd>
          <dt>Environment</dt><dd>{data.environment}</dd>
          <dt>API version</dt><dd><code>{data.version}</code></dd>
          <dt>Answered by pod</dt><dd><code>{data.hostname}</code></dd>
        </dl>
      )}
      <button onClick={load}>Call the API again</button>
    </main>
  );
}
