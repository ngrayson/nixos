// Scrying Orb — Discord bot: /task (→ Notion), /scry (post the digest), inbox-channel capture.
// Gateway (outbound websocket) only; no inbound port.
//   /task <title> [priority] [area] [due] [who]   → one row in Nick's Tasks
//   the owner reacts :crylaugh: to a message in the inbox channel → that message becomes a task, with
//   inline tokens: p0-p3, #area, due:<date|fri|+3d>, @agent|@collab. Plain messages are left alone, so
//   the channel can also carry other captures (Nick files Conveyor tasks there too).
// Env (same file as digest.mjs): NOTION_TOKEN, DISCORD_BOT_TOKEN, DISCORD_GUILD_ID, DISCORD_OWNER_ID
// (only this user may create tasks), optional DISCORD_INBOX_CHANNEL_ID and DISCORD_CAPTURE_EMOJI
// (emoji name, default "crylaugh"). The grammar and the Notion
// schema come from task.mjs, so scry-task, hearth-tui and this bot file tasks identically.
import { Client, GatewayIntentBits, Partials, REST, Routes, SlashCommandBuilder, MessageFlags } from "discord.js";
import { existsSync, readFileSync } from "node:fs";
import { execFile } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { PRIORITIES, WHO, areas, createTask, parseDue, parseInbox } from "./task.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const env = { ...process.env };
if (existsSync(join(here, ".env")))
  for (const line of readFileSync(join(here, ".env"), "utf8").split("\n")) {
    const m = line.match(/^([A-Z_]+)=(.*)$/);
    if (m && !env[m[1]]) env[m[1]] = m[2];
  }
for (const k of ["NOTION_TOKEN", "DISCORD_BOT_TOKEN", "DISCORD_GUILD_ID", "DISCORD_OWNER_ID"]) if (!env[k]) throw new Error(`missing ${k}`);

const client = new Client({
  intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages, GatewayIntentBits.GuildMessageReactions, GatewayIntentBits.MessageContent],
  // Reactions on messages sent before the bot (re)connected arrive as partials and are fetched on demand.
  partials: [Partials.Message, Partials.Channel, Partials.Reaction, Partials.User],
});
const taskCommand = new SlashCommandBuilder()
  .setName("task").setDescription("File a task in Nick's Tasks (Notion)")
  .addStringOption((o) => o.setName("title").setDescription("What").setRequired(true))
  .addStringOption((o) => o.setName("priority").setDescription("P0–P3").addChoices(...PRIORITIES.map((p) => ({ name: p, value: p }))))
  .addStringOption((o) => o.setName("area").setDescription("Area").setAutocomplete(true))
  .addStringOption((o) => o.setName("due").setDescription("2026-10-04 · oct 4 · fri · +3d"))
  .addStringOption((o) => o.setName("who").setDescription("Type").addChoices(...WHO.map((w) => ({ name: w, value: w }))));
const scryCommand = new SlashCommandBuilder().setName("scry").setDescription("Post the scry digest now");

// /scry runs digest.mjs --post as a child: same env (secrets), same node, no systemctl (the bot is
// an unprivileged DynamicUser). Its digest.md/json land in the bot's own SCRY_OUT, not scry.service's.
const runDigest = () => new Promise((resolve, reject) =>
  execFile(process.execPath, [join(here, "digest.mjs"), "--post"], { env, timeout: 180e3 }, (err, _stdout, stderr) =>
    err ? reject(new Error((stderr || err.message).split("\n").filter(Boolean).slice(-3).join(" | "))) : resolve(stderr.trim())));

client.once("clientReady", async () => {
  await new REST().setToken(env.DISCORD_BOT_TOKEN).put(Routes.applicationGuildCommands(client.user.id, env.DISCORD_GUILD_ID), { body: [taskCommand.toJSON(), scryCommand.toJSON()] });
  console.log(`ready as ${client.user.tag}; /task and /scry registered in guild ${env.DISCORD_GUILD_ID}; inbox ${env.DISCORD_INBOX_CHANNEL_ID ? `on (:${CAPTURE_EMOJI}: reactions)` : "off"}`);
});

const isOwner = (id) => id === env.DISCORD_OWNER_ID;
const CAPTURE_EMOJI = env.DISCORD_CAPTURE_EMOJI || "crylaugh";
const summary = (t, url) => `✅ [${t.title}](<${url}>)` + [t.priority, t.area && `#${t.area}`, t.due && `due ${t.due}`, t.who && t.who !== "Nick" && t.who].filter(Boolean).map((x) => ` · ${x}`).join("");

client.on("interactionCreate", async (i) => {
  try {
    if (i.isAutocomplete() && i.commandName === "task") {
      const q = i.options.getFocused().toLowerCase();
      return i.respond((await areas()).filter((a) => a.name.toLowerCase().includes(q)).slice(0, 25).map((a) => ({ name: a.name, value: a.name })));
    }
    if (!i.isChatInputCommand()) return;
    if (!isOwner(i.user.id)) return i.reply({ content: "not for you", flags: MessageFlags.Ephemeral });
    if (i.commandName === "scry") {
      await i.deferReply({ flags: MessageFlags.Ephemeral });
      const note = await runDigest();
      return i.editReply(`🔮 ${note || "posted"}`);
    }
    if (i.commandName !== "task") return;
    await i.deferReply({ flags: MessageFlags.Ephemeral });
    const t = { title: i.options.getString("title"), priority: i.options.getString("priority"), area: i.options.getString("area"), due: parseDue(i.options.getString("due")), who: i.options.getString("who") };
    const url = await createTask(t);
    await i.editReply(summary(t, url));
  } catch (e) {
    const msg = `❌ ${e.message}`;
    if (i.deferred || i.replied) await i.editReply(msg).catch(() => {});
    else if (i.isRepliable()) await i.reply({ content: msg, flags: MessageFlags.Ephemeral }).catch(() => {});
  }
});

// Inbox capture: only a message the owner reacts to with the capture emoji is filed. Its author can be
// anyone; the owner's reaction is the authorisation. The bot's own ✅ marks a message as already
// filed, so a second reaction (or removing and re-adding one) never files it twice.
client.on("messageReactionAdd", async (reaction, user) => {
  if (!env.DISCORD_INBOX_CHANNEL_ID || reaction.message.channelId !== env.DISCORD_INBOX_CHANNEL_ID) return;
  if (user.bot || !isOwner(user.id)) return;
  try {
    if (reaction.partial) await reaction.fetch();
  } catch {
    return;
  }
  if (reaction.emoji.name !== CAPTURE_EMOJI) return;
  let m;
  try {
    m = reaction.message.partial ? await reaction.message.fetch() : reaction.message;
  } catch {
    return;
  }
  if (m.reactions.cache.get("✅")?.me) return;
  try {
    const t = parseInbox(m.content);
    const url = await createTask(t);
    await m.react("✅");
    await m.reply({ content: summary(t, url), allowedMentions: { repliedUser: false } });
  } catch (e) {
    await m.react("❌").catch(() => {});
    await m.reply({ content: `❌ ${e.message}`, allowedMentions: { repliedUser: false } }).catch(() => {});
  }
});

client.login(env.DISCORD_BOT_TOKEN);
