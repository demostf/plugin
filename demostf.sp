#pragma semicolon 1
#include <sourcemod>
#include <cURL>

public Plugin:myinfo =
{
	name = "demos.tf uploader",
	author = "Icewind",
	description = "Auto-upload match stv to demos.tf",
	version = "0.3.1",
	url = "https://demos.tf"
};

new CURL_Default_opt[][2] = {
	{_:CURLOPT_NOSIGNAL,1},
	{_:CURLOPT_NOPROGRESS,1},
	{_:CURLOPT_TIMEOUT,600},
	{_:CURLOPT_CONNECTTIMEOUT,600},
	{_:CURLOPT_USE_SSL,CURLUSESSL_TRY},
	{_:CURLOPT_SSL_VERIFYPEER,0},
	{_:CURLOPT_SSL_VERIFYHOST,0},
	{_:CURLOPT_VERBOSE,0}
};

/**
 * Converts a string to lowercase
 *
 * @param buffer		String to convert
 * @noreturn
 */
public CStrToLower(String:buffer[]) {
	new len = strlen(buffer);
	for(new i = 0; i < len; i++) {
		buffer[i] = CharToLower(buffer[i]);
	}
}

#define CURL_DEFAULT_OPT(%1) curl_easy_setopt_int_array(%1, CURL_Default_opt, sizeof(CURL_Default_opt))

new String:g_sDemoName[256] = "";
new String:g_sLastDemoName[256] = "";

new Handle:g_hCvarAPIKey = INVALID_HANDLE;
new Handle:g_hCvarUrl = INVALID_HANDLE;
new Handle:output_file = INVALID_HANDLE;
new Handle:postForm = INVALID_HANDLE;
new Handle:g_hCvarRedTeamName = INVALID_HANDLE;
new Handle:g_hCvarBlueTeamName = INVALID_HANDLE;

new Handle:g_hDemoUploaded = INVALID_HANDLE;

public OnPluginStart()
{
	g_hCvarAPIKey = CreateConVar("sm_demostf_apikey", "", "API key for demos.tf", FCVAR_PROTECTED);
	g_hCvarUrl = CreateConVar("sm_demostf_url", "https://demos.tf", "demos.tf url", FCVAR_PROTECTED);
	g_hCvarRedTeamName = FindConVar("mp_tournament_redteamname");
	g_hCvarBlueTeamName = FindConVar("mp_tournament_blueteamname");
	
	g_hDemoUploaded = CreateGlobalForward("DemoUploaded", ET_Ignore, Param_Cell, Param_String, Param_String);

	RegServerCmd("tv_record", Command_StartRecord);
	RegServerCmd("tv_stoprecord", Command_StopRecord);
}

public OnPluginEnd()
{
	CloseHandle(g_hDemoUploaded);
}

public Action:Command_StartRecord(args)
{
	if (strlen(g_sDemoName) == 0) {
		GetCmdArgString(g_sDemoName, sizeof(g_sDemoName));
		StripQuotes(g_sDemoName);
		CStrToLower(g_sDemoName);
	}
	return Plugin_Continue;
}

public Action:Command_StopRecord(args)
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

public Action:StartDemoUpload(Handle:timer)
{
	decl String:fullPath[128];
	Format(fullPath, sizeof(fullPath), "%s.dem", g_sLastDemoName);
	UploadDemo(fullPath);
}

UploadDemo(const String:fullPath[])
{
	decl String:APIKey[128];
	GetConVarString(g_hCvarAPIKey, APIKey, sizeof(APIKey));
	decl String:BaseUrl[64];
	GetConVarString(g_hCvarUrl, BaseUrl, sizeof(BaseUrl));
	new String:Map[64];
	GetCurrentMap(Map, sizeof(Map));
	PrintToChatAll("[demos.tf]: Uploading demo %s", fullPath);
	new Handle:curl = curl_easy_init();
	CURL_DEFAULT_OPT(curl);
	decl String:bluname[128];
	decl String:redname[128];
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
	decl String:fullUrl[128];
	Format(fullUrl, sizeof(fullUrl), "%s/upload", BaseUrl);
	curl_easy_setopt_string(curl, CURLOPT_URL, fullUrl);
	curl_easy_perform_thread(curl, onComplete);
}

public onComplete(Handle:hndl, CURLcode:code)
{
	if(code != CURLE_OK)
	{
		new String:error_buffer[256];
		curl_easy_strerror(code, error_buffer, sizeof(error_buffer));
		CloseHandle(output_file);
		CloseHandle(hndl);
		PrintToChatAll("cURLCode error: %d", code);
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

public ShowResponse()
{
	new Handle:resultFile = OpenFile("output_demo.json", "r");
	new String:output[512];
	ReadFileString(resultFile, output, sizeof(output));
	PrintToChatAll("[demos.tf]: %s", output);
	LogToGame("[demos.tf]: %s", output);

	new String:demoid[16];
	new String:url[256];

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
