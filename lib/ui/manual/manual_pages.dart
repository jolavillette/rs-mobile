// The pages of the manual, in the Markdown the desktop's manual uses:
// headings, paragraphs, lists, **bold**, `code` and links to other pages
// written [text](page.md). Kept in the code so that the manual works without
// a network and without an asset list to maintain.

const manualPages = <String, String>{
  'index': '''
# Manual

RetroShare Mobile runs a RetroShare node on this phone. It connects only to
the nodes of the people you added as friends, every connection is encrypted,
and there is no central server.

- [Getting started](start.md)
- [Home](home.md): your RetroShare ID, adding a friend
- [Network](network.md): your friends' nodes
- [People](people.md): identities and contacts
- [Chat](chats.md): chats and chat rooms
- [Room history](history.md): the lines you missed
- [Forums and Channels](forums.md)
- [The phone in the background](background.md)
- [Preferences](preferences.md)
- [Chat settings](chat-settings.md)
- [Permissions](permissions.md): the services of the node
- [Statistics](statistics.md): bandwidth and battery

The button **?** at the top of a page opens the part of this manual that
explains it.
''',
  'start': '''
# Getting started

Three notions are worth knowing:

- Your **profile** is your key pair, protected by your password. It is what
  your friends accept when they add you.
- Your **node** is this installation of RetroShare. One profile can have
  several nodes, for instance this phone and a desktop.
- Your **identities** are the names under which you write in chat rooms,
  forums and channels. See [People](people.md).

## How to

1. **Create a profile** at the first start: a name and a password.
2. **Exchange RetroShare IDs with a friend.** [Home](home.md) shows yours.
   Both of you must add the other one.
3. **Wait for the connection.** Your friend then shows as connected in
   [Network](network.md).
4. **Join the conversations** in [Chat](chats.md).

## A friend on a desktop

A phone is often asleep, on a mobile network or without a network. A friend
whose desktop runs RetroShare all the time keeps the phone in touch while it
sleeps: see [The phone in the background](background.md). Have at least one
such friend.
''',
  'home': '''
# Home

Home shows **your RetroShare ID**, the text a friend needs to add you.

- **Short** or **Long**: the short ID is enough with recent versions of
  RetroShare; the long one carries your whole certificate.
- **Copy**, **Share** and **QR code** give it to your friend the way you
  like.

## Add a friend

Under "Did you receive a RetroShare ID from your friend?", **Add Friend**
takes the ID your friend gave you, pasted or scanned from a QR code.

Both of you must add the other one. A friend added with a short ID is
confirmed once the first connection has exchanged your keys.
''',
  'network': '''
# Network

Network lists your friends' nodes, connected or not, and your open direct
chats.

- At the top, your own node: your status (available, away, busy) and a
  status message, and the picture of your node.
- Tap a friend's node for its details: name, node ID, addresses, last
  contact, the version it runs.

## Node details

- **Attempt to connect** asks your node to call this friend now. It is
  available while the friend is not connected.
- **Send message** opens a direct chat with the node. A message sent while
  the friend is offline waits until the friend connects.
- The RetroShare ID of the node can be copied, to give it to another node
  of yours.
- **Remove node** removes this node only; **Remove friend** removes the
  friend and all their nodes.
''',
  'people': '''
# People

People lists the **identities**: your own ones, your contacts, and all the
identities your node knows of, met in chat rooms, forums and channels.

- **Create New Identity**: a **signed** identity shows that it belongs to
  your profile; a **pseudonymous** one cannot be tied to your profile by
  anybody, not even your friends.
- **Add to contacts** keeps an identity in your contacts.
- **Start chat** opens a distant chat with an identity: an encrypted
  conversation through the network, without being friends.
''',
  'chats': '''
# Chat

Chat lists your open chats, the invitations you received, the chat rooms
you are subscribed to and the public rooms you can join.

- **Join** enters a public room; **Leave room** leaves it.
- An invitation shows the room and who invited you: **Join** or
  **Decline**.

## In a room

The menu at the top right of a room gives:

- **Search** and **Clear chat**,
- **Participants**: who is in the room,
- **History from friends**: the lines you missed, see
  [Room history](history.md),
- **Identity in this room**: the identity you write under,
- **Invite friends** and **Leave room**.

The button beside the text field attaches a picture, a file or a video. A
file is posted as a RetroShare link: your friends download it from your
phone, so keep RetroShare running until they have it.

## Notifications

With the app in the background, a notification comes for a direct or
distant chat message, a room line that mentions your name, an invitation,
and the first line of a room after five minutes of silence. The other lines
of a room are kept by your friend's desktop until you come back: see
[The phone in the background](background.md).
''',
  'history': '''
# Room history

The phone keeps the lines of the rooms it receives (Chat settings,
**Chat Rooms History**) and shows the last ones when you open a room. The
lines sent while the phone was off or out of reach can be asked to friends
that were in the room.

## Ask your friends

1. Designate the friends to ask, once: [Chat settings](chat-settings.md),
   **Friends asked for the history**, or **Designate the friends to ask** in
   the dialog of step 2.
2. In the room, menu, **History from friends**, then choose how far back:
   the last hour, 6 hours, 24 hours or 7 days.
3. The lines you do not have yet are added to the chat, in the order they
   were written.

## Choose trusted friends

The lines a friend sends are **not signed**: a friend could send lines that
nobody wrote. They show the name the friend gives, without an identity.
Select only friends you trust, such as your own desktop.

## When nothing comes

A friend answers only:

- if it allows the sharing of its history, in its own chat settings (off by
  default on the desktop),
- if it is connected and in the room, and already sees this phone in it:
  just after a connection, ask again a minute later,
- once every 30 seconds for the same room: the app tells you when you can
  ask again.

"Nothing new" means that your friends have no line that is missing here.
''',
  'forums': '''
# Forums and Channels

Forums and Channels show the forums and channels your friends share, and
the posts of those you subscribe to. The app reads them; it does not post.

Both services are off at first: synchronizing them costs data, battery and
storage, channels most of all. Each page has a button to turn its service
on; [Permissions](permissions.md) turns them off again.
''',
  'background': '''
# The phone in the background

When you leave the app, RetroShare keeps running in the background, shown by
a permanent notification. To spare the battery and the mobile data, it
relies on the friends whose desktop runs RetroShare: they act as the
phone's **homes**.

- The phone sleeps. Every few minutes it wakes up briefly to tell its homes
  that it is still there.
- A direct or distant chat message, a room line that mentions you and an
  invitation reach the phone at once and show a notification.
- The other lines of a room are kept by the home and delivered when you open
  the app again; the first line after five minutes of silence comes at once,
  with a notification.
- The lines a home keeps are held in its memory: if the home restarts, ask
  them to your friends, see [Room history](history.md).

Without a home connected, the phone still sleeps, and calls its homes each
time it wakes up.

What this costs is shown in [Statistics](statistics.md), tab **Battery**.
''',
  'preferences': '''
# Preferences

- **Node**: your profile, this node and its RetroShare ID.
- **Network**: the addresses of this node, the DHT, and whether this node
  relays the tunnels and searches of other nodes.
- **Chats**: see [Chat settings](chat-settings.md).
- **Appearance**: the theme, light, dark or the one of the device.
- **Permissions**: the services of the node, see
  [Permissions](permissions.md).
- **RetroShare**: the versions of the app and of its libraries.

## Network

- **Use the DHT** finds friends whose address changed. Off saves a little
  battery and data, but a friend whose address changed may stay out of
  reach.
- **Relay for other nodes** passes on the tunnel and search requests of
  other nodes. Off saves battery and data.
''',
  'chat-settings': '''
# Chat settings

- **Message Bubble Style** and **Theme Mode**: how the chats look.
- **Accept chat from**: who may open a distant chat with you: everyone,
  your contacts only, or nobody.

## History

- **Distant Chats History**, **Chat Rooms History** and
  **Private Chats History** keep the messages on the phone, so that a chat
  shows its last lines when you open it again.
- **Friends asked for the history**: the friends asked for the lines of a
  room you missed. Select only friends you trust: see
  [Room history](history.md).
''',
  'permissions': '''
# Permissions

Permissions lists every service the RetroShare core runs on this phone, in
groups:

- **Needed by the app**: chats, rooms, identities, the link with your homes
  and what keeps the connections healthy. They cannot be turned off here.
- **The app works without**: **Discovery** exchanges addresses, keys and
  versions with your friends. Turned off, the phone no longer learns its
  friends' new addresses nor tells them its own, a friend added with a short
  ID stays unverified, and the friends' versions are no longer shown.
- **No page in the app**: services the app cannot show, such as mail, file
  lists or boards. They are off: they would use processor, data, battery and
  storage for nothing you can see. The app turns them off at every start,
  except those you turn on here.
''',
  'statistics': '''
# Statistics

Statistics has two tabs.

## Bandwidth

The traffic of the node, received and sent: the speeds over the last
seconds in kB/s, and the totals in MB since RetroShare started on this
phone; then the same for each service. Tap a column to sort by it.

## Battery

What RetroShare costs the phone, over the last time in background, the last
24 hours and the last 7 days. Pull down to measure again.

- **RetroShare**: its average processor use, the seconds per hour it keeps
  the phone awake, how often it wakes the phone (for a keep-alive, for an
  arrival), and its packets and kB per hour on Wi-Fi and on the mobile
  network.
- **Battery of the phone**: how long the phone was awake, what the battery
  lost in mAh and %, the average current, and the rate per day. This counts
  every application, not RetroShare alone.
- **RetroShare, as Android counts it**: the battery Android charges to
  RetroShare, in mAh. This part shows only once Android lets RetroShare
  read it, which takes a computer with adb, once:

`adb shell pm grant cc.retroshare.retroshare android.permission.BATTERY_STATS`

`adb shell pm grant cc.retroshare.retroshare android.permission.DUMP`

The figures build up while RetroShare runs: they are taken each time the
phone wakes up anyway, never by waking it.
''',
};
