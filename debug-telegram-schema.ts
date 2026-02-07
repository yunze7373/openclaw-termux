import { TelegramAccountSchemaBase } from "./src/config/zod-schema.providers-core.js";

async function run() {
  const schema = TelegramAccountSchemaBase as any;
  console.log("Calling toJSONSchema with options...");
  
  const json = schema.toJSONSchema({
    target: "draft-07",
    unrepresentable: "any",
  });
  
  const customCommands = json.properties?.customCommands;
  console.log("customCommands schema:", JSON.stringify(customCommands, null, 2));
  
  if (customCommands?.items) {
      console.log("Items:", JSON.stringify(customCommands.items, null, 2));
  }
}

run().catch(console.error);