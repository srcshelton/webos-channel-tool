# webos-channel-tool

Shell utility to save custom channel numbers from Goldstar/LG webOS TV saved data files, and restore post-retune.

```
Usage:
	webos-channel-tool.sh --save < GlobalClone00001.TLL | tee channel.list
	webos-channel-tool.sh --show < channel.list
	webos-channel-tool.sh --apply [GlobalClone00001.TLL] < channel.list | tee GlobalClone00001.TLL
```

*A backup is required _PRIOR_ to re-tuning*

Intended usage:

Before re-tuning -
 * Use the webOS (impressively UK-localised) `All Settings` -> `Programmes` -> `Programme Manager` tool's `Edit All Programmes` '`Edit Programme Numbers`' option to re-number channels as required;
 * Whilst the addition of new channels is non-destructive, re-tuning will reset channels to their default numbers.  Due to the way Freeview channels are organised, mandatory re-tuning is required semi-regularly;
 * Attach an NTFS-formatted USB storage device, and choose `All Settings` -> `Programmes` -> `Copy Programmes` -> `TV to USB` to write a file named '`GlobalClone00001.TLL`' to the device;
 * Remove the USB storage device and connect to a computer running at least bash-4 (noting that, as standard, macOS still uses bash-3.x - but updated versions can be obtained via [Homebrew](https://brew.sh)) and run `webos-channel-tool.sh --save < GlobalClone00001.TLL > channel.list` in the same directory as `GlobalClone00001.TLL` has been copied to in order to save your customisations to a portable list;
 * It is now safe to re-tune your television.

After re-tuning -
 * As above, generate another `GlobalClone00001.TLL` after re-tuning, save it to a USB storage device, and copy it to you computer;
 * Run `webos-channel-tool.sh --apply GlobalClone00001.TLL < channel.list > GlobalClone00001.TLL.new && mv GlobalClone00001.TLL.new GlobalClone00001.TLL` to update the new channel data with the previously stored channel numbers;
 * Copy the updated `GlobalClone00001.TLL` back to your USB storage device device, plug it back into the television, and choose `All Settings` -> `Programmes` -> `Copy Programmes` -> `USB to TV` to reload the programme list.

Please note that a fresh `GlobalClone00001.TLL` straight from a re-tuned television contains a lot of junk - and we pointedly avoid completely re-writing it, instead only updating the specified channel number for existing entries.  This means that removed channels stay gone, and there is very little chance of anything not working.  There is basic non back-referencing reordering logic to move duplicated radio stations to unused channels between 700 and 799, and duplicated channels to 800 and higher.  After loading the data from this tool, some radio channels may appear as DTV channels - and when first selected, the TV will revert to the last viewed TV channel after a few seconds.  This action will also, however, reset the entire contiguous block of radio channels back to being regarded as radio services.
