<?php

session_start();

$userID = $_SESSION['userID'];

if ($userID !== null) // se un utente già loggato scrive a mano "login.php"...
{
    header("Location: logout.php"); // lo sloggo!
    exit();
}

?>

<html>

<body>
    <h1>please log in</h1>

    <form action="verify.php" method="post">
        username: <input type="text" name="name"><br><br>
        password: <input type="password" name="password"><br><br>
        <input type="submit">
    </form>

    <?php

    $msg = htmlspecialchars($_GET['m']);

    if ($msg == 1)
        echo "invalid username or password";
    if ($msg == 2)
        echo "please insert username and password";
    if ($msg == 3)
        echo "logged out successfully";

    ?>

</body>

</html>