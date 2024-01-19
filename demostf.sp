#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <cURL>

public Plugin myinfo =
{
	name = "demos.tf uploader",
	author = "Icewind / sappho.io",
	description = "Auto-upload match stv to demos.tf",
	version = "0.3.2",
	url = "https://demos.tf"
};

int CURL_Default_opt[][2] = {
	{ view_as<int>(CURLOPT_NOSIGNAL),               1 }, 
	{ view_as<int>(CURLOPT_NOPROGRESS),             1 }, 
	{ view_as<int>(CURLOPT_TIMEOUT),                30 }, 
	{ view_as<int>(CURLOPT_CONNECTTIMEOUT),         30 }, 
	{ view_as<int>(CURLOPT_USE_SSL),                CURLUSESSL_ALL }, 
	{ view_as<int>(CURLOPT_VERBOSE),                0 }
};


/**
 * Converts a string to lowercase
 *
 * @param buffer		String to convert
 * @noreturn
 */
public void CStrToLower(char[] buffer) {
	int len = strlen(buffer);
	for(int  i = 0; i < len; i++) {
		buffer[i] = CharToLower(buffer[i]);
	}
}

#define CURL_DEFAULT_OPT(%1) curl_easy_setopt_int_array( %1, CURL_Default_opt, sizeof(CURL_Default_opt) )

char g_sDemoName[256] = "";
char g_sLastDemoName[256] = "";

Handle g_hCvarAPIKey = INVALID_HANDLE;
Handle g_hCvarUrl = INVALID_HANDLE;
Handle output_file = INVALID_HANDLE;
Handle postForm = INVALID_HANDLE;
Handle g_hCvarRedTeamName = INVALID_HANDLE;
Handle g_hCvarBlueTeamName = INVALID_HANDLE;

Handle g_hDemoUploaded = INVALID_HANDLE;

public void OnPluginStart()
{
	g_hCvarAPIKey = CreateConVar("sm_demostf_apikey", "", "API key for demos.tf", FCVAR_PROTECTED);
	g_hCvarUrl = CreateConVar("sm_demostf_url", "https://demos.tf", "demos.tf url", FCVAR_PROTECTED);
	g_hCvarRedTeamName = FindConVar("mp_tournament_redteamname");
	g_hCvarBlueTeamName = FindConVar("mp_tournament_blueteamname");
	
	g_hDemoUploaded = CreateGlobalForward("DemoUploaded", ET_Ignore, Param_Cell, Param_String, Param_String);

	RegServerCmd("tv_record", Command_StartRecord);
	RegServerCmd("tv_stoprecord", Command_StopRecord);
}

public void OnPluginEnd()
{
	CloseHandle(g_hDemoUploaded);
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
		LogMessage("Demo recording completed");
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
	return Plugin_Continue;
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
	LogMessage("Uploading demo %s", fullPath);

	Handle curl = curl_easy_init();
	if (!curl)
	{
		LogError("Couldn't init curl handle!");
	}


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

public void onComplete(Handle hndl, CURLcode code)
{
	if(code != CURLE_OK)
	{
		char error_buffer[256];
		curl_easy_strerror(code, error_buffer, sizeof(error_buffer));
		CloseHandle(output_file);
		CloseHandle(hndl);

		PrintToChatAll("cURLCode error: %s", error_buffer);
		LogError("cURLCode error: %s", error_buffer);

		CallDemoUploaded(false, "", "");
	}
	else
	{
		CloseHandle(output_file);
		CloseHandle(hndl);
		ShowResponse();
	}
	CloseHandle(postForm);
	return;
}

void ShowResponse()
{
	Handle resultFile = OpenFile("output_demo.json", "r");
	char output[512];
	ReadFileString(resultFile, output, sizeof(output));
	PrintToChatAll("[demos.tf]: %s", output);
	LogToGame("[demos.tf]: %s", output);
	LogMessage("%s", output);

	char demoid[16];
	char url[256];

	char url_parts[4][16];

	strcopy(url, sizeof(url), output);

	if (StrContains(url, "STV available at: ") != -1)
	{
		// Get the url part
		ReplaceString(url, sizeof(url), "STV available at: ", "");
		// Split the string on '/'
		ExplodeString(url, "/", url_parts, sizeof(url_parts), sizeof(url_parts[]));

		// Find the last part of the url
		for (int i = sizeof(url_parts) -1; i >= 0; i--)
		{
			if (!StrEqual(url_parts[i], "")){
				demoid = url_parts[i];
				break;
			}
		}
		CallDemoUploaded(true, demoid, url);
		return;
	}
	
	CallDemoUploaded(false, "", "");
	return;
}


void CallDemoUploaded(bool success, const char[] demoid, const char[] url) {
	Call_StartForward(g_hDemoUploaded);

	// Push parameters one at a time
	Call_PushCell(success);
	Call_PushString(demoid);
	Call_PushString(url);

	// Finish the call
	Call_Finish();
}
