<?php
// Create connection
$mySQLconnection = mysqli_connect("localhost:3306", "root", "scp2014", "drmDemo");

// Check connection
if (mysqli_connect_errno())
    echo "Failed to connect to MySQL: " . mysqli_connect_error();
else
    echo "connection to database succesful!<br>";


// stampo table users
$users = mysqli_query($mySQLconnection, "SELECT * FROM Users");
echo "<br>Table: users";
echo "<table border='1'>
<tr>
<th>Id</th>
<th>Name</th>
<th>md5 password</th>
</tr>";
printTable($users);
echo "</table>";

// stampo table video URLs
$videos = mysqli_query($mySQLconnection, "SELECT * FROM Videourls");
echo "<br>Table: video URLS";
echo "<table border='1'>
<tr>
<th>axoid</th>
<th>url</th>
</tr>";
printTable($videos);
echo "</table>";

// stampo table video Keys
$videoKeys = mysqli_query($mySQLconnection, "SELECT * FROM Videokeys");
echo "<br>Table: video KEYS";
echo "<table border='1'>
<tr>
<th>axoid</th>
<th>algorithmID</th>
<th>bufferSize</th>
<th>key</th>
</tr>";
printTable($videoKeys);
echo "</table>";

// stampo table rights
$rights = mysqli_query($mySQLconnection, "SELECT * FROM rights");
echo "<br>Table: rights";
echo "<table border='1'>
<tr>
<th>Id</th>
<th>user ID</th>
<th>video ID</th>
</tr>";
printTable($rights);
echo "</table>";


function printTable($query)
{
    while ($row = mysqli_fetch_array($query)) {
        echo "<tr>";
        for ($i = 0; $i < count($row); $i++) {
            echo "<td>" . $row[$i] . "</td>";
        }
        echo "</tr>";
    }
}
