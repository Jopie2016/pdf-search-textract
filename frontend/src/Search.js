import React, { useState } from "react";

function Search() {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function handleSearch(e) {
    const q = e.target.value;
    setQuery(q);
    console.log("Search query:", q);

    if (q.length > 1) {
      setLoading(true);
      setError("");
      try {
        // CloudFront proxies /search to API Gateway → Lambda
        console.log("Fetching:", `/search?q=${encodeURIComponent(q)}`);
        const res = await fetch(`/search?q=${encodeURIComponent(q)}`);
        console.log("Response status:", res.status);
        if (!res.ok) {
          throw new Error(`API error: ${res.status}`);
        }
        const data = await res.json();
        console.log("Search results:", data);
        setResults(data.results || []);
      } catch (err) {
        console.error("Search failed:", err);
        setError(`Search request failed: ${err.message}`);
        setResults([]);
      } finally {
        setLoading(false);
      }
    } else {
      setResults([]);
    }
  }

  return (
    <div style={{ padding: "20px", fontFamily: "Arial, sans-serif" }}>
      <h2>PDF Search</h2>

      <input
        value={query}
        onChange={handleSearch}
        placeholder="Search FDA PDFs..."
        style={{ width: "400px", padding: "8px", marginBottom: "12px" }}
      />

      {loading && <p>Loading...</p>}
      {error && <p style={{ color: "red" }}>{error}</p>}

      <ul>
        {results.map((r, i) => (
          <li key={i} style={{ marginBottom: "16px" }}>
            <strong>{r.filename}</strong>
            <br />
            <span
              dangerouslySetInnerHTML={{
                __html: r.snippet || "(no snippet available)"
              }}
            />
            {r.url && (
              <div>
                {" "}
                <a
                  href={r.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  style={{ color: "blue" }}
                >
                  Open PDF
                </a>
              </div>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}

export default Search;
