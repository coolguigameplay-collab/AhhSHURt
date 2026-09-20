package backend;

import openfl.utils.Assets;

import haxe.Json;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

typedef ModsList = {
	enabled:Array<String>,
	disabled:Array<String>,
	all:Array<String>
};

class Mods
{
	public static var currentModDirectory:String = '';

	public static final ignoreModFolders:Array<String> = [
		'characters',
		'custom_events',
		'custom_notetypes',
		'data',
		'songs',
		'music',
		'sounds',
		'shaders',
		'videos',
		'images',
		'stages',
		'weeks',
		'fonts',
		'scripts',
		'achievements'
	];

	private static var globalMods:Array<String> = [];

	inline public static function getGlobalMods():Array<String>
	{
		return globalMods;
	}

	inline public static function pushGlobalMods():Array<String>
	{
		globalMods = [];

		for (mod in parseList().enabled)
		{
			var pack:Dynamic = getPack(mod);

			if (pack != null)
			{
				try
				{
					if (pack.runsGlobally)
						globalMods.push(mod);
				}
				catch(e:Dynamic)
				{
					// No runsGlobally field.
				}
			}
		}

		return globalMods;
	}

	/**
	 * Returns the embedded mod directories.
	 *
	 * Embedded mods are stored inside:
	 *
	 * assets -> mods -> ModName
	 *
	 * because Project.xml maps:
	 *
	 * example_mods -> mods
	 */
	public static function getModDirectories():Array<String>
	{
		var list:Array<String> = [];

		#if MODS_ALLOWED

		/*
		 * Desktop:
		 * Keep support for a real external mods directory when available.
		 */
		#if sys

		var externalMods:String = Paths.mods();

		if (FileSystem.exists(externalMods) && FileSystem.isDirectory(externalMods))
		{
			try
			{
				for (folder in FileSystem.readDirectory(externalMods))
				{
					var path:String = haxe.io.Path.join([externalMods, folder]);

					if (FileSystem.isDirectory(path)
						&& !ignoreModFolders.contains(folder.toLowerCase())
						&& !list.contains(folder))
					{
						list.push(folder);
					}
				}
			}
			catch(e:Dynamic)
			{
				trace('Mods: unable to read external mods directory: $e');
			}
		}

		#end

		/*
		 * Embedded APK/project assets.
		 *
		 * Example:
		 *
		 * mods/BikiniHorrorsV3/images/foo.png
		 *
		 * becomes:
		 *
		 * BikiniHorrorsV3
		 */
		for (asset in Assets.list())
		{
			if (asset == null)
				continue;

			var normalized:String = asset.replace('\\', '/');

			if (!normalized.startsWith('mods/'))
				continue;

			var remaining:String = normalized.substr(5);

			if (remaining.length == 0)
				continue;

			var slash:Int = remaining.indexOf('/');

			if (slash <= 0)
				continue;

			var modName:String = remaining.substr(0, slash);

			if (modName.length == 0)
				continue;

			if (ignoreModFolders.contains(modName.toLowerCase()))
				continue;

			if (!list.contains(modName))
				list.push(modName);
		}

		#end

		return list;
	}

	inline public static function mergeAllTextsNamed(
		path:String,
		?defaultDirectory:String = null,
		allowDuplicates:Bool = false
	)
	{
		if (defaultDirectory == null)
			defaultDirectory = Paths.getSharedPath();

		defaultDirectory = defaultDirectory.trim();

		if (!defaultDirectory.endsWith('/'))
			defaultDirectory += '/';

		if (!defaultDirectory.startsWith('assets/'))
			defaultDirectory = 'assets/$defaultDirectory';

		var mergedList:Array<String> = [];
		var paths:Array<String> = directoriesWithFile(defaultDirectory, path);

		var defaultPath:String = defaultDirectory + path;

		if (paths.contains(defaultPath))
		{
			paths.remove(defaultPath);
			paths.insert(0, defaultPath);
		}

		for (file in paths)
		{
			var list:Array<String> = CoolUtil.coolTextFile(file);

			for (value in list)
			{
				if (
					(allowDuplicates || !mergedList.contains(value))
					&& value.length > 0
				)
				{
					mergedList.push(value);
				}
			}
		}

		return mergedList;
	}

	/**
	 * Finds files from:
	 *
	 * 1. Default/shared assets
	 * 2. Current level
	 * 3. Global embedded mods
	 * 4. Current embedded mod
	 */
	inline public static function directoriesWithFile(
		path:String,
		fileToFind:String,
		mods:Bool = true
	)
	{
		var foldersToCheck:Array<String> = [];

		if (Paths.assetExists(path + fileToFind))
			foldersToCheck.push(path + fileToFind);

		if (
			Paths.currentLevel != null
			&& Paths.currentLevel != path
		)
		{
			var pth:String = Paths.getFolderPath(
				fileToFind,
				Paths.currentLevel
			);

			if (
				!foldersToCheck.contains(pth)
				&& Paths.assetExists(pth)
			)
			{
				foldersToCheck.push(pth);
			}
		}

		#if MODS_ALLOWED

		if (mods)
		{
			for (mod in Mods.getGlobalMods())
			{
				var folder:String = Paths.mods(
					mod + '/' + fileToFind
				);

				if (
					Paths.assetExists(folder)
					&& !foldersToCheck.contains(folder)
				)
				{
					foldersToCheck.push(folder);
				}
			}

			var folder:String = Paths.mods(fileToFind);

			if (
				Paths.assetExists(folder)
				&& !foldersToCheck.contains(folder)
			)
			{
				foldersToCheck.push(folder);
			}

			if (
				Mods.currentModDirectory != null
				&& Mods.currentModDirectory.length > 0
			)
			{
				var current:String = Paths.mods(
					Mods.currentModDirectory + '/' + fileToFind
				);

				if (
					Paths.assetExists(current)
					&& !foldersToCheck.contains(current)
				)
				{
					foldersToCheck.push(current);
				}
			}
		}

		#end

		return foldersToCheck;
	}

	public static function getPack(?folder:String = null):Dynamic
	{
		#if MODS_ALLOWED

		if (folder == null)
			folder = Mods.currentModDirectory;

		if (folder == null || folder.length == 0)
			return null;

		var path:String = Paths.mods(folder + '/pack.json');

		/*
		 * Embedded APK asset.
		 */
		if (Paths.assetExists(path))
		{
			try
			{
				var rawJson:String = Assets.getText(path);

				if (rawJson != null && rawJson.length > 0)
					return tjson.TJSON.parse(rawJson);
			}
			catch(e:Dynamic)
			{
				trace('Mods: failed to read pack.json: $e');
			}
		}

		/*
		 * External desktop mod fallback.
		 */
		#if sys

		if (FileSystem.exists(path))
		{
			try
			{
				var rawJson:String = File.getContent(path);

				if (rawJson != null && rawJson.length > 0)
					return tjson.TJSON.parse(rawJson);
			}
			catch(e:Dynamic)
			{
				trace('Mods: failed to read external pack.json: $e');
			}
		}

		#end

		#end

		return null;
	}

	public static var updatedOnState:Bool = false;

	public static function parseList():ModsList
	{
		if (!updatedOnState)
			updateModList();

		var list:ModsList = {
			enabled: [],
			disabled: [],
			all: []
		};

		#if MODS_ALLOWED

		/*
		 * Embedded modsList.txt.
		 *
		 * Project.xml:
		 *
		 * list.txt -> modsList.txt
		 */
		if (Paths.assetExists('modsList.txt'))
		{
			try
			{
				var raw:String = Assets.getText('modsList.txt');

				if (raw != null)
				{
					for (mod in raw.split('\n'))
					{
						mod = mod.trim();

						if (mod.length < 1)
							continue;

						var dat:Array<String> = mod.split('|');
						var name:String = dat[0].trim();

						if (name.length == 0)
							continue;

						list.all.push(name);

						if (
							dat.length > 1
							&& dat[1].trim() == '1'
						)
						{
							list.enabled.push(name);
						}
						else
						{
							list.disabled.push(name);
						}
					}
				}
			}
			catch(e:Dynamic)
			{
				trace('Mods: failed to parse embedded modsList.txt: $e');
			}
		}

		/*
		 * If no list.txt is supplied or it is empty,
		 * automatically enable every embedded mod.
		 */
		if (list.all.length == 0)
		{
			for (folder in getModDirectories())
			{
				if (!list.all.contains(folder))
				{
					list.all.push(folder);
					list.enabled.push(folder);
				}
			}
		}
		else
		{
			/*
			 * Add embedded mods which aren't listed.
			 */
			for (folder in getModDirectories())
			{
				if (!list.all.contains(folder))
				{
					list.all.push(folder);
					list.enabled.push(folder);
				}
			}
		}

		#end

		return list;
	}

	private static function updateModList()
	{
		#if MODS_ALLOWED

		/*
		 * Embedded APK assets are immutable.
		 *
		 * Therefore we DO NOT call File.saveContent()
		 * on Android anymore.
		 */
		var list:ModsList = {
			enabled: [],
			disabled: [],
			all: []
		};

		/*
		 * First read the bundled list.
		 */
		if (Paths.assetExists('modsList.txt'))
		{
			try
			{
				var raw:String = Assets.getText('modsList.txt');

				if (raw != null)
				{
					for (line in raw.split('\n'))
					{
						line = line.trim();

						if (line.length == 0)
							continue;

						var dat:Array<String> = line.split('|');
						var name:String = dat[0].trim();

						if (name.length == 0)
							continue;

						var enabled:Bool =
							dat.length > 1
							&& dat[1].trim() == '1';

						list.all.push(name);

						if (enabled)
							list.enabled.push(name);
						else
							list.disabled.push(name);
					}
				}
			}
			catch(e:Dynamic)
			{
				trace('Mods: updateModList failed: $e');
			}
		}

		/*
		 * Automatically detect embedded mods.
		 */
		for (folder in getModDirectories())
		{
			if (!list.all.contains(folder))
			{
				list.all.push(folder);
				list.enabled.push(folder);
			}
		}

		/*
		 * On desktop, preserve the old writable external
		 * modsList.txt behavior when an external mods folder exists.
		 */
		#if sys

		var externalMods:String = Paths.mods();

		if (
			FileSystem.exists(externalMods)
			&& FileSystem.isDirectory(externalMods)
		)
		{
			try
			{
				var externalList:Array<Array<Dynamic>> = [];
				var added:Array<String> = [];

				if (FileSystem.exists('modsList.txt'))
				{
					for (mod in CoolUtil.coolTextFile('modsList.txt'))
					{
						var dat:Array<String> = mod.split('|');

						if (dat.length == 0)
							continue;

						var folder:String = dat[0].trim();

						if (
							folder.length > 0
							&& FileSystem.exists(Paths.mods(folder))
							&& FileSystem.isDirectory(Paths.mods(folder))
							&& !added.contains(folder)
						)
						{
							added.push(folder);

							externalList.push([
								folder,
								dat.length > 1 && dat[1] == '1'
							]);
						}
					}
				}

				for (folder in getModDirectories())
				{
					if (
						folder.length > 0
						&& !added.contains(folder)
					)
					{
						added.push(folder);
						externalList.push([folder, true]);
					}
				}

				var fileStr:String = '';

				for (values in externalList)
				{
					if (fileStr.length > 0)
						fileStr += '\n';

					fileStr +=
						values[0]
						+ '|'
						+ (values[1] ? '1' : '0');
				}

				File.saveContent('modsList.txt', fileStr);
			}
			catch(e:Dynamic)
			{
				trace('Mods: unable to update desktop modsList.txt: $e');
			}
		}

		#end

		updatedOnState = true;

		#end
	}

	public static function loadTopMod()
	{
		Mods.currentModDirectory = '';

		#if MODS_ALLOWED

		var list:Array<String> = Mods.parseList().enabled;

		if (list != null && list.length > 0)
		{
			Mods.currentModDirectory = list[0];
		}

		#end
	}

	/**
	 * Returns true when an embedded asset exists.
	 */
	public static function embeddedAssetExists(path:String):Bool
	{
		if (path == null || path.length == 0)
			return false;

		return Paths.assetExists(path);
	}
}
