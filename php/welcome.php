<?php

session_start();

$userID = $_SESSION['userID']; // da verify.php

if ($userID === null) {
    header("Location: login.php?m=2");
    exit();
}


$keysProviderURL = "https://localhost/mySQLdemo/keysProvider.php";

$_SESSION['$keysProviderURL'] = $keysProviderURL;

?>

<html>

<body>
    <?php
    $mySQLconnection = mysqli_connect("localhost:3306", "root", "scp2014", "drmDemo");

    // Check connection
    //if (mysqli_connect_errno())
    //    echo "Failed to connect to MySQL: " . mysqli_connect_error();
    //else
    //    echo "connection to database succesful!<br>";


    $userName = $_SESSION['username']; // da verify.php
    echo "<br> Welcome, $userName. <a href='logout.php'>[logout]</a><br>";

    //$userQuery = mysqli_query($mySQLconnection, "SELECT * FROM users WHERE id = '$userID'");
    //echo "<br>your credentials:";
    //echo "<table border='1'>
    //<tr>
    //<th>user ID</th>
    //<th>user name</th>
    //<th>md5 password</th>
    //</tr>";
    //printTable($userQuery);
    //echo "</table>";

    //NON dividere la stringa di query su più linee (col punto) altrimenti NON funziona!!!
    //$rightsQuery = mysqli_query($mySQLconnection,"SELECT rights.ID, rights.userID, users.name, rights.videoID, videourls.url, videokeys.key FROM rights LEFT JOIN users ON rights.userID = users.ID LEFT JOIN videourls ON rights.videoID = videourls.axoid LEFT JOIN videokeys ON rights.videoID = videokeys.axoid WHERE users.id = '$userID'");
    // nota che l'ho fatta giusta al primo tentativo!!! Incredibile!!!
    $rightsQuery = mysqli_query($mySQLconnection, "SELECT rights.ID, rights.userID, users.name, rights.videoID FROM rights LEFT JOIN users ON rights.userID = users.ID WHERE users.id = '$userID'");

    echo "<br>your rights:";
    echo "<table border='1'>
<tr>
<th>right ID</th>
<th>user ID</th>
<th>user name</th>
<th>video ID</th>
</tr>";
    printTable($rightsQuery);
    echo "</table>";



    $videosQuery = mysqli_query($mySQLconnection, "SELECT * FROM Videourls");
    //echo "<br>print ALL the videos!";
    echo "<br>complete video list:";
    echo "<table border='1'>
<tr>
<th>video ID</th>
<th>url</th>
</tr>";
    printVideosTable($videosQuery);
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


    function printVideosTable($query)
    {
        while ($row = mysqli_fetch_array($query)) {
            echo "<tr>";
            for ($i = 0; $i < count($row); $i++) {
                echo "<td>" . $row[$i] . "</td>";
            }
            echo "<td><a href='player.php?axoid=$row[axoid]'>click to watch video</a></td>";
            echo "</tr>";
        }
    }



    ?>
</body>

</html>