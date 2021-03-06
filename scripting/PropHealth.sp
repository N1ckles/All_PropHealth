#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <zombiereloaded>
#include <multicolors>

#pragma newdecls required
#pragma semicolon 1

#define PL_VERSION "1.2"
#define MAXENTITIES 2048

public Plugin myinfo =
{
	name = "[All] Prop Health",
	author = "Roy (Christian Deacon) (minor fixes by N1ckles)",
	description = "Props now have health!",
	version = PL_VERSION,
	url = "GFLClan.com && TheDevelopingCommunity.com"
};

// ConVars
ConVar g_cvConfigPath = null;
ConVar g_cvDefaultHealth = null;
ConVar g_cvDefaultMultiplier = null;
ConVar g_cvColor = null;
ConVar g_cvTeamRestriction = null;
ConVar g_cvPrint = null;
ConVar g_cvPrintType = null;
ConVar g_cvPrintMessage = null;
ConVar g_cvDebug = null;
ConVar g_cvMaxHealth = null;

// ConVar Values
char g_sConfigPath[PLATFORM_MAX_PATH];
int g_iDefaultHealth;
float g_fDefaultMultiplier;
char g_sColor[32];
int g_iTeamRestriction;
bool g_bPrint;
int g_iPrintType;
char g_sPrintMessage[256];
bool g_bDebug;
int g_iMaxHealth;

// Other Variables
int g_aiPropHealth[MAXENTITIES + 1];
float g_afPropMultiplier[MAXENTITIES + 1];
char g_sLogFile[PLATFORM_MAX_PATH];

public void OnPluginStart()
{
	// ConVars
	CreateConVar("sm_ph_version", PL_VERSION, "Prop Health's version.");
	
	g_cvConfigPath = CreateConVar("sm_ph_config_path", "configs/prophealth.props.cfg", "The path to the Prop Health config.");
	g_cvDefaultHealth = CreateConVar("sm_ph_default_health", "-1", "A prop's default health if not defined in the config file. -1 = Doesn't break.");
	g_cvDefaultMultiplier = CreateConVar("sm_ph_default_multiplier", "325.00", "Default multiplier based on the player count (for zombies/humans). Default: 65 * 5 (65 damage by right-click knife with 5 hits)");
	g_cvColor = CreateConVar("sm_ph_color", "255 0 0 255", "If a prop has a color, set it to this color. -1 = no color. uses RGBA.");
	g_cvTeamRestriction = CreateConVar("sm_ph_team", "2", "What team are allowed to destroy props? 0 = no restriction, 1 = humans, 2 = zombies.");
	g_cvPrint = CreateConVar("sm_ph_print", "1", "Print the prop's health when damaged to the attacker's chat?");
	g_cvPrintType = CreateConVar("sm_ph_print_type", "1", "The print type (if \"sm_ph_print\" is set to 1). 1 = PrintToChat, 2 = PrintCenterText, 3 = PrintHintText.");
	g_cvPrintMessage = CreateConVar("sm_ph_print_message", "{darkred}[PH]{default}Prop Health: {lightgreen}%i", "The message to send to the client. Multicolors supported only for PrintToChat. %i = health value.");
	g_cvDebug = CreateConVar("sm_ph_debug", "0", "Enable debugging (logging will go to logs/prophealth-debug.log).");
	g_cvMaxHealth = CreateConVar("sm_ph_maxhealth", "0", "Maximum health for props (0=no max)");
	
	AutoExecConfig(true, "plugin.prop-health");
	
	// Commands
	RegConsoleCmd("sm_getpropinfo", Command_GetPropInfo);
}

void LoadSettings(){
	GetConVarString(g_cvConfigPath, g_sConfigPath, sizeof(g_sConfigPath));
	g_iDefaultHealth = GetConVarInt(g_cvDefaultHealth);
	g_fDefaultMultiplier = GetConVarFloat(g_cvDefaultMultiplier);
	GetConVarString(g_cvColor, g_sColor, sizeof(g_sColor));
	g_iTeamRestriction = GetConVarInt(g_cvTeamRestriction);
	g_bPrint = GetConVarBool(g_cvPrint);
	g_iPrintType = GetConVarInt(g_cvPrintType);
	GetConVarString(g_cvPrintMessage, g_sPrintMessage, sizeof(g_sPrintMessage));
	g_bDebug = GetConVarBool(g_cvDebug);
	g_iMaxHealth = GetConVarInt(g_cvMaxHealth);
	
	BuildPath(Path_SM, g_sLogFile, sizeof(g_sLogFile), "logs/prophealth-debug.log");
}

public void CVarChanged(ConVar hCVar, const char[] sOldV, char[] sNewV)
{
	LoadSettings();
}

public void OnConfigsExecuted()
{
	// Load settings after config is executed:
	LoadSettings();
	
	// Hook changes afterwards to avoid CVarChanged spam
	HookConVarChange(g_cvConfigPath, CVarChanged);
	HookConVarChange(g_cvDefaultHealth, CVarChanged);	
	HookConVarChange(g_cvDefaultMultiplier, CVarChanged);	
	HookConVarChange(g_cvColor, CVarChanged);	
	HookConVarChange(g_cvTeamRestriction, CVarChanged);		
	HookConVarChange(g_cvPrint, CVarChanged);		
	HookConVarChange(g_cvPrintType, CVarChanged);		
	HookConVarChange(g_cvPrintMessage, CVarChanged);	
	HookConVarChange(g_cvDebug, CVarChanged);
	HookConVarChange(g_cvMaxHealth, CVarChanged);
}

public void OnMapStart()
{
	PrecacheSound("physics/metal/metal_box_break1.wav");
	PrecacheSound("physics/metal/metal_box_break2.wav");
}

public void OnEntityCreated(int iEnt, const char[] sClassname)
{
	if (iEnt > MaxClients)
	{
		SDKHook(iEnt, SDKHook_SpawnPost, OnEntitySpawned);
	}
}

public void OnEntitySpawned(int iEnt)
{
	if (IsValidEntity(iEnt))
	{
		g_aiPropHealth[iEnt] = -1;
		g_afPropMultiplier[iEnt] = 0.0;
		SetPropHealth(iEnt);
	}
}

public Action Hook_OnTakeDamage(int iEnt, int &iAttacker, int &iInflictor, float &fDamage, int &iDamageType)
{
	if (!iAttacker || iAttacker > MaxClients || !IsClientInGame(iAttacker))
	{
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop %i returned. Attacker (%i) not valid.", iEnt, iAttacker);
		}
		
		return Plugin_Continue;
	}
	
	if (!IsValidEntity(iEnt) || !IsValidEdict(iEnt))
	{
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop %i returned. Prop not valid.", iEnt, iAttacker);
		}
		
		return Plugin_Continue;
	}
	
	if (g_aiPropHealth[iEnt] < 0)
	{
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop %i returned. Prop health under 0.", iEnt, iAttacker);
		}
		
		return Plugin_Continue;
	}
	
	if (g_iTeamRestriction == 1 && ZR_IsClientZombie(iAttacker))
	{
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop %i returned. Attacker (%i) not on the right team.", iEnt, iAttacker);
		}
		
		return Plugin_Continue;
	}	
	
	if (g_iTeamRestriction == 2 && ZR_IsClientHuman(iAttacker))
	{
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop %i returned. Attacker (%i) not on the right team.", iEnt, iAttacker);
		}
		
		return Plugin_Continue;
	}
	
	g_aiPropHealth[iEnt] -= RoundToZero(fDamage);
	
	if (g_bDebug)
	{
		LogToFile(g_sLogFile, "Prop Damaged (Prop: %i) (Damage: %f) (Health: %i)", iEnt, fDamage, g_aiPropHealth[iEnt]);
	}
	
	if (g_aiPropHealth[iEnt] < 1)
	{
		// Destroy the prop.
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop Destroyed (Prop: %i)", iEnt);
		}
		
		AcceptEntityInput(iEnt, "kill");
		RemoveEdict(iEnt);
		
		g_aiPropHealth[iEnt] = -1;
	}
	
	// Play a sound.
	int iRand = GetRandomInt(1, 2);
	switch (iRand)
	{
		case 1:
		{
			float fPos[3];
			GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", fPos);
			EmitSoundToAll("physics/metal/metal_box_break1.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, fPos);
		}
		case 2:
		{
			float fPos[3];
			GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", fPos);
			EmitSoundToAll("physics/metal/metal_box_break2.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, fPos);
		}
	}
	
	// Print To Client
	if (g_bPrint && g_aiPropHealth[iEnt] > 0)
	{
		if (g_iPrintType == 1)
		{
			// Print To Chat.
			CPrintToChat(iAttacker, g_sPrintMessage, g_aiPropHealth[iEnt]);
		}
		else if (g_iPrintType == 2)
		{
			// Print Center Text.
			PrintCenterText(iAttacker, g_sPrintMessage, g_aiPropHealth[iEnt]);
		}
		else if (g_iPrintType == 3)
		{
			// Print Hint Text.
			PrintHintText(iAttacker, g_sPrintMessage, g_aiPropHealth[iEnt]);
		}
	}
	
	return Plugin_Continue;
}

public Action Command_GetPropInfo(int iClient, int iArgs)
{
	int iEnt = GetClientAimTarget(iClient, false);
	
	if (iEnt > MaxClients && IsValidEntity(iEnt))
	{
		char sModelName[PLATFORM_MAX_PATH];
		GetEntPropString(iEnt, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
		PrintToChat(iClient, "\x03[PH]\x02(Model: %s) (Prop Health: %i) (Prop Index: %i)", sModelName, g_aiPropHealth[iEnt], iEnt);
	}
	else
	{
		PrintToChat(iClient, "\x03[PH]\x02Prop is either a player or invalid. (Prop Index: %i)", iEnt);
	}
	
	return Plugin_Handled;
}

stock void SetPropHealth(int iEnt)
{
	char sClassname[MAX_NAME_LENGTH];
	GetEntityClassname(iEnt, sClassname, sizeof(sClassname));
	
	if (!StrEqual(sClassname, "prop_physics", false) && !StrEqual(sClassname, "prop_physics_override", false) && !StrEqual(sClassname, "prop_physics_multiplayer", false))
	{
		return;
	}

	char sFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, sizeof(sFile), g_sConfigPath);
	
	KeyValues hKV = CreateKeyValues("Props");
	hKV.ImportFromFile(sFile);
	
	char sPropModel[PLATFORM_MAX_PATH];
	GetEntPropString(iEnt, Prop_Data, "m_ModelName", sPropModel, sizeof(sPropModel));
	if (g_bDebug)
	{
		LogToFile(g_sLogFile, "Prop model found! (Prop: %i) (Prop Model: %s)", iEnt, sPropModel);
	}
	
	if (hKV.GotoFirstSubKey())
	{
		char sBuffer[PLATFORM_MAX_PATH];
		do
		{
			hKV.GetSectionName(sBuffer, sizeof(sBuffer));
			if (g_bDebug)
			{
				LogToFile(g_sLogFile, "Checking prop model. (Prop: %i) (Prop Model: %s) (Section Model: %s)", iEnt, sPropModel, sBuffer);
			}
			
			if (StrEqual(sBuffer, sPropModel, false))
			{
				if (g_bDebug)
				{
					LogToFile(g_sLogFile, "Prop model matches. (Prop: %i) (Prop Model: %s)", iEnt, sPropModel);
				}
				
				g_aiPropHealth[iEnt] = hKV.GetNum("health");
				
				float fMultiplier2 = hKV.GetFloat("multiplier");
				int iClientCount = GetRealClientCount();
				float fAddHealth = view_as<float>(iClientCount) * fMultiplier2;
				
				g_aiPropHealth[iEnt] += RoundToZero(fAddHealth);
				g_afPropMultiplier[iEnt] = fMultiplier2;
				
				if (g_bDebug)
				{
					LogToFile(g_sLogFile, "Custom prop's health set. (Prop: %i) (Prop Health: %i) (Multiplier: %f) (Added Health: %i) (Client Count: %i)", iEnt, g_aiPropHealth[iEnt], fMultiplier2, RoundToZero(fAddHealth), iClientCount);
				}
			}
		} while (hKV.GotoNextKey());
	}
	
	if (hKV != null)
	{
		delete hKV;
	}
	else
	{			
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "hKV was never valid.");
		}
	}
	
	if (g_aiPropHealth[iEnt] < 1)
	{
		g_aiPropHealth[iEnt] = g_iDefaultHealth;
		g_afPropMultiplier[iEnt] = g_fDefaultMultiplier;
		
		int iClientCount = GetRealClientCount();
		float fAddHealth = float(iClientCount) * g_fDefaultMultiplier;
		
		g_aiPropHealth[iEnt] += RoundToZero(fAddHealth);
		
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop is being set to default health. (Prop: %i) (O - Default Health: %i) (Default Multiplier: %f) (Added Health: %i) (Health: %i) (Client Count: %i)", iEnt, g_iDefaultHealth, g_fDefaultMultiplier, RoundToZero(fAddHealth), g_aiPropHealth[iEnt], iClientCount);
		}
	}
	else
	{
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop already has a health value! (Prop: %i) (Health: %i)", iEnt, g_aiPropHealth[iEnt]);
		}
	}
	
	if (g_aiPropHealth[iEnt] > 0 && !StrEqual(g_sColor, "-1", false))
	{
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop is being colored! (Prop: %i)", iEnt);
		}
		
		// Set the entities color.
		char sBit[4][32];
		
		ExplodeString(g_sColor, " ", sBit, sizeof (sBit), sizeof (sBit[]));
		SetEntityRenderColor(iEnt, StringToInt(sBit[0]), StringToInt(sBit[1]), StringToInt(sBit[2]), StringToInt(sBit[3]));
	}
	
	if(g_iMaxHealth > 0 && g_aiPropHealth[iEnt] > g_iMaxHealth){
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop exceeded max health. Health set to max. (Prop: %i) (Previous health: %i) (Max health: %f)", iEnt, g_aiPropHealth[iEnt], g_iMaxHealth);
		}
		g_aiPropHealth[iEnt] = g_iMaxHealth;
	}
	
	if (g_aiPropHealth[iEnt] > 0)
	{
		SDKHook(iEnt, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	}
}

stock int GetRealClientCount()
{
	int iCount;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) != 1)
		{
			iCount++;
		}
	}
	
	return iCount;
}