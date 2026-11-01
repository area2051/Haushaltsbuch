CREATE TABLE "sync_meta" (
	"id" boolean PRIMARY KEY DEFAULT true NOT NULL,
	"resync_floor" bigint DEFAULT 0 NOT NULL,
	CONSTRAINT "sync_meta_single_row" CHECK ("sync_meta"."id")
);
--> statement-breakpoint
-- Seed the single row (hand-added; drizzle-kit does not generate data statements).
INSERT INTO "sync_meta" ("id") VALUES (true) ON CONFLICT DO NOTHING;
