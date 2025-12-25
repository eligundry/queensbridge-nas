# Study

You have access to the following commands:

```bash
# Access the nas
ssh nas
```

# Context

This repo is a glorified docker compose for my Synology NAS. This goes through
"Container Manager", which seems to be docker compatible, but you probably know
more. The `DATA_DIR` in @docker-compose.yml is `/home/eligundry` and we want to
keep it like that.

It has a couple of issues that I needed fixed:

1. Deployments require me to copy and paste the config in to it. Every two times
   I copy and paste it, the networking breaks and I need to restart the whole
   thing. What I would love is a local deploy script that would `sftp` the files
   up, `ssh` in, and apply the docker change. I'm assuming that the
   docker-compose lives somewhere in the file system.
2. There are some config files that I've had to manually copy to the NAS that
   are outside of VC, which is bad.
3. After those two things are fixed, the big issue is that I cannot access the
   plex container. When I attempt to access it at `https://it-was-written.tail7aee2.ts.net:8445`,
   I get redirected to `https://it-was-written.tail7aee2.ts.net`. We need have
   it be accessible like that.

# Tasks

1. Collect all configuration files referenced into the docker compose. It could
   be in a subdirectory, I do not really care. Some of these are only on the
   nas, so you'll need to download them.
2. Create a script that syncs these files up to the correct locations. You'll
   need to do some research on where Container Manager stores things.
3. Loop on making fixes until you can get a dailtone from the Plex server
   through caddy
