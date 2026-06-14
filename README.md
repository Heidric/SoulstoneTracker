# SoulstoneTracker

WoW 1.12 addon for tracking the active `Soulstone Resurrection` applied by the current player.

SuperWoW + SuperAPI are recommended. Without SuperWoW, target tracking falls back to normal `SPELLCAST_*` events and can only approximate the target from the current friendly target or mouseover state.

## Soulstone announcements

Announcements are disabled by default. Enable them in the Notifications tab or with:

```text
/sst announce on
```

Available channels:

```text
SMART, SAY, PARTY, RAID, GUILD, YELL, EMOTE
```

`SMART` resolves to `RAID` if you are in a raid, then `PARTY` if you are in a party, otherwise `SAY`.

Default message:

```text
Soulstone applied to {target}. It will expire in {duration}.
```

Supported placeholders:

```text
{target}
{name} - alias for the {target}
{player} - name of the warlock themselves
{duration}
```

Slash examples:

```text
/sst announce channel SMART
/sst announce channel RAID
/sst announce text Soulstone applied to {target}. Please keep it until wipe recovery.
/sst announce test
/sst announce off
```

## Commands

```text
/sst options
/sst status
/sst clear
/sst lock
/sst unlock
/sst show
/sst hide
/sst reset
/sst scale 1.2
/sst pos
/sst button reset
/sst button show
/sst button hide
/sst test TargetName 120
```
