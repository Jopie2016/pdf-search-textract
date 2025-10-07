import React, { useState } from "react";

function Search() {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState([]);
  const [pagination, setPagination] = useState(null);
  const [currentPage, setCurrentPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function performSearch(q, page = 1) {
    setLoading(true);
    setError("");
    try {
      console.log(`Fetching: /search?q=${encodeURIComponent(q)}&page=${page}`);
      const res = await fetch(`/search?q=${encodeURIComponent(q)}&page=${page}`);
      console.log("Response status:", res.status);
      if (!res.ok) {
        throw new Error(`API error: ${res.status}`);
      }
      const data = await res.json();
      console.log("Search results:", data);
      setResults(data.results || []);
      setPagination(data.pagination || null);
      setCurrentPage(page);
    } catch (err) {
      console.error("Search failed:", err);
      setError(`Search request failed: ${err.message}`);
      setResults([]);
      setPagination(null);
    } finally {
      setLoading(false);
    }
  }

  async function handleSearch(e) {
    const q = e.target.value;
    setQuery(q);
    console.log("Search query:", q);

    if (q.length > 1) {
      performSearch(q, 1); // Always start at page 1 for new search
    } else {
      setResults([]);
      setPagination(null);
    }
  }

  function handleNextPage() {
    if (pagination && pagination.has_next) {
      performSearch(query, currentPage + 1);
    }
  }

  function handlePrevPage() {
    if (pagination && pagination.has_prev) {
      performSearch(query, currentPage - 1);
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

      {pagination && (
        <div style={{ marginBottom: "12px", color: "#666" }}>
          Showing {results.length} of {pagination.total_results} results
          {pagination.total_pages > 1 && ` (Page ${pagination.current_page} of ${pagination.total_pages})`}
        </div>
      )}

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

      {pagination && pagination.total_pages > 1 && (
        <div style={{ marginTop: "20px", display: "flex", gap: "10px", alignItems: "center" }}>
          <button
            onClick={handlePrevPage}
            disabled={!pagination.has_prev}
            style={{
              padding: "8px 16px",
              cursor: pagination.has_prev ? "pointer" : "not-allowed",
              opacity: pagination.has_prev ? 1 : 0.5,
              backgroundColor: "#007bff",
              color: "white",
              border: "none",
              borderRadius: "4px"
            }}
          >
            ← Previous
          </button>

          <span>
            Page {pagination.current_page} of {pagination.total_pages}
          </span>

          <button
            onClick={handleNextPage}
            disabled={!pagination.has_next}
            style={{
              padding: "8px 16px",
              cursor: pagination.has_next ? "pointer" : "not-allowed",
              opacity: pagination.has_next ? 1 : 0.5,
              backgroundColor: "#007bff",
              color: "white",
              border: "none",
              borderRadius: "4px"
            }}
          >
            Next →
          </button>
        </div>
      )}
    </div>
  );
}

export default Search;
