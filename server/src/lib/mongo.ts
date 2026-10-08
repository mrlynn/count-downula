import { MongoClient, type Db } from "mongodb";

const globalForMongo = globalThis as unknown as { _countdownulaMongo?: Promise<MongoClient> };

function client(): Promise<MongoClient> {
  const uri = process.env.MONGODB_URI;
  if (!uri) throw new Error("MONGODB_URI is not set.");
  // Reuse one client across hot reloads and warm serverless invocations.
  globalForMongo._countdownulaMongo ??= new MongoClient(uri, { appName: "countdownula-server" }).connect();
  return globalForMongo._countdownulaMongo;
}

export async function db(): Promise<Db> {
  return (await client()).db(process.env.MONGODB_DB ?? "countdownula");
}
