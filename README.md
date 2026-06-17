# Why?

Frigate NVR is a fantastic piece of software, however even though you set a retention date, sometimes it leaves files behind. Maybe something crashed, maybe they were locked or in use.  If you delete/rename a camera, it won't clean up the files from the old camera name either. The Devs seem uninterested in resolving this, hence this script.

### Requirements
_yq_ is required. Typically *apt install yq* in most cases.

# How it works

Modify the script at the top for the file paths to your Frigate Data Directory, the location of your Frigate config.yml File, and where you want the Log File saved.

When run, the script will read your configuration file to determine your camera names. It will also look at all of your _retain: days:_ and use the highest value (+1 day for safety) to determine the age of the files to be removed. The script only targets the specific Frigate directories where the normal automatic removal of data should have taken place but failed.

The default mode is a "dry run" so you can see some stats about what will happen (see below.) Running the script with -delete will remove the stale files and directories.

I have done my best to add as many checks as I can think of so that nothing besides the targeted files/directories will be removed.  I use it myself on my own install, but please be cautious on your own system.

# Example "Dry Run" Output
```
------------------------------------------
Frigate Cleanup Script
ℹ️ Mode: DRY RUN
------------------------------------------

Configuration:
📹 Cameras configured : 11
  Cameras:
    - Backyard
    - Deckside
    - Downstairs
    - Driveway
    - Frontyard
    - Garage
    - Garage2
    - HouseBackyard
    - HouseSideyard
    - Kitchen
    - Sideyard

🔁 Retention : 10 days (effective=11)

🔍 Scanning recordings...
🔍 Scanning clips...

------------------------------------------
Cleanup Summary
------------------------------------------

📁 Recordings
  Folders to remove : 1

🎞 Clips

  ⏳ Aged Files
    Files : 1880
    Size  : 1.8M

  📊 Total
    Files : 1880
    Size  : 1.8M

📂 Orphan Camera Directories
  Names:
    Moose
    Rachels
    Poolside

------------------------------------------
ℹ️ Mode: DRY RUN
------------------------------------------
```
