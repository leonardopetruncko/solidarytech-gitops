CREATE TABLE IF NOT EXISTS donations (
    id SERIAL PRIMARY KEY,
    ngo_id INT NOT NULL,
    amount NUMERIC(10, 2) NOT NULL,
    donor_name VARCHAR(100) NOT NULL,
    status VARCHAR(20) NOT NULL, -- Ex: APPROVED, PENDING
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Consultas por ONG (relatórios de arrecadação) sem varrer a tabela inteira.
CREATE INDEX IF NOT EXISTS idx_donations_ngo_id ON donations (ngo_id);
