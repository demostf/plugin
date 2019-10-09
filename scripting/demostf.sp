#include <sourcemod>
#include <cURL>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "demos.tf uploader",
	author = "Icewind, B3none",
	description = "Auto-upload match stv to demos.tf",
	version = "0.3",
	url = "https://demos.tf"
};

CURL_Default_opt[][2] = {
	{view_as<int>(CURLOPT_NOSIGNAL), 1},
	{view_as<int>(CURLOPT_NOPROGRESS), 1},
	{view_as<int>(CURLOPT_TIMEOUT), 120},
	{view_as<int>(CURLOPT_CONNECTTIMEOUT), 120},
	{view_as<int>(CURLOPT_USE_SSL),CURLUSESSL_TRY},
	{view_as<int>(CURLOPT_SSL_VERIFYPEER), 0},
	{view_as<int>(CURLOPT_SSL_VERIFYHOST), 0},
	{view_as<int>(CURLOPT_VERBOSE), 0}
};

/**
 * Converts a string to lowercase
 *
 * @param buffer		String to convert
 * @noreturn
 */
public void CStrToLower(char[] buffer) {
	int len = strlen(buffer);
	for (int i = 0; i < len; i++) {
		buffer[i] = CharToLower(buffer[i]);
	}
}

#define CURL_DEFAULT_OPT(%1) curl_easy_setopt_int_array(%1, CURL_Default_opt, sizeof(CURL_Default_opt))

char g_sDemoName[256] = "";
char g_sLastDemoName[256] = "";

Handle g_hCvarAPIKey = null;
Handle g_hCvarUrl = null;
Handle output_file = null;
Handle postForm = null;
Handle g_hCvarRedTeamName = null;
Handle g_hCvarBlueTeamName = null;

public void OnPluginStart()
{
	g_hCvarAPIKey = CreateConVar("sm_demostf_apikey", "", "API key for demos.tf", FCVAR_PROTECTED);
	g_hCvarUrl = CreateConVar("sm_demostf_url", "https://demos.tf", "demos.tf url", FCVAR_PROTECTED);
	g_hCvarRedTeamName = FindConVar("mp_tournament_redteamname");
	g_hCvarBlueTeamName = FindConVar("mp_tournament_blueteamname");
	
	RegServerCmd("tv_record", Command_StartRecord);
	RegServerCmd("tv_stoprecord", Command_StopRecord);
}

public Action Command_StartRecord(int args)
{
	if (strlen(g_sDemoName) == 0) {
		GetCmdArgString(g_sDemoName, sizeof(g_sDemoName));
		StripQuotes(g_sDemoName);
		CStrToLower(g_sDemoName);
	}
	
	return Plugin_Continue;
}

public Action Command_StopRecord(int args)
{
	TrimString(g_sDemoName);
	
	if (strlen(g_sDemoName) != 0) {
		PrintToChatAll("[demos.tf]: Demo recording completed");
		g_sLastDemoName = g_sDemoName;
		g_sDemoName = "";
		CreateTimer(3.0, StartDemoUpload);
	}
	
	return Plugin_Continue;
}

public Action StartDemoUpload(Handle timer)
{
	char fullPath[128];
	Format(fullPath, sizeof(fullPath), "%s.dem", g_sLastDemoName);
	UploadDemo(fullPath);
}

void UploadDemo(const char[] fullPath)
{
	char APIKey[128];
	GetConVarString(g_hCvarAPIKey, APIKey, sizeof(APIKey));
	char BaseUrl[64];
	GetConVarString(g_hCvarUrl, BaseUrl, sizeof(BaseUrl));
	char Map[64];
	GetCurrentMap(Map, sizeof(Map));
	PrintToChatAll("[demos.tf]: Uploading demo %s", fullPath);
	Handle curl = curl_easy_init();
	CURL_DEFAULT_OPT(curl);
	char bluname[128];
	char redname[128];
	GetConVarString(g_hCvarRedTeamName, redname, sizeof(redname));
	GetConVarString(g_hCvarBlueTeamName, bluname, sizeof(bluname));
	
	postForm = curl_httppost();
	curl_formadd(postForm, CURLFORM_COPYNAME, "demo", CURLFORM_FILE, fullPath, CURLFORM_END);
	curl_formadd(postForm, CURLFORM_COPYNAME, "name", CURLFORM_COPYCONTENTS, fullPath, CURLFORM_END);
	curl_formadd(postForm, CURLFORM_COPYNAME, "red", CURLFORM_COPYCONTENTS, redname, CURLFORM_END);
	curl_formadd(postForm, CURLFORM_COPYNAME, "blu", CURLFORM_COPYCONTENTS, bluname, CURLFORM_END);
 	curl_formadd(postForm, CURLFORM_COPYNAME, "key", CURLFORM_COPYCONTENTS, APIKey, CURLFORM_END);
	curl_easy_setopt_handle(curl, CURLOPT_HTTPPOST, postForm);

	output_file = curl_OpenFile("output_demo.json", "w");
	curl_easy_setopt_handle(curl, CURLOPT_WRITEDATA, output_file);
	char fullUrl[128];
	Format(fullUrl, sizeof(fullUrl), "%s/upload", BaseUrl);
	curl_easy_setopt_string(curl, CURLOPT_URL, fullUrl);
	curl_easy_perform_thread(curl, onComplete);
}

public bool onComplete(Handle hndl, CURLcode code)
{
	if (code != CURLE_OK) {
		char error_buffer[256];
		curl_easy_strerror(code, error_buffer, sizeof(error_buffer));
		CloseHandle(output_file);
		CloseHandle(hndl);
		PrintToChatAll("cURLCode error: %d", code);
	} else {
		CloseHandle(output_file);
		CloseHandle(hndl);
		ShowResponse();
	}
	
	CloseHandle(postForm);
}

public void ShowResponse()
{
	Handle resultFile = OpenFile("output_demo.json", "r");
	char output[512];
	ReadFileString(resultFile, output, sizeof(output));
	PrintToChatAll("[demos.tf]: %s", output);
}
